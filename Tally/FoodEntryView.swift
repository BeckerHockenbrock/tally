import SwiftUI
import SwiftData

enum FoodEntryMode: String, CaseIterable, Identifiable {
    case search, barcode
    var id: String { rawValue }
    var title: String { self == .search ? "Foods" : "Barcode" }
}

struct FoodEntryView: View {
    @EnvironmentObject private var feedback: TallyFeedback
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedFood.lastUsedAt, order: .reverse) private var savedFoods: [SavedFood]
    let initialDate: Date
    var followsToday = true
    var initialMode = FoodEntryMode.search
    var startingBarcode: String?
    var startingFood: Food?
    @State private var mode = FoodEntryMode.search
    @State private var started = false
    @State private var query = ""
    @State private var barcode = ""
    @State private var isUPCE = false
    @State private var showingScanner = false
    @State private var showingManual = false
    @State private var manualNutrition: FoodNutrition?
    @State private var pendingBarcode: String?
    @State private var selectedFood: Food?
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var cacheWarning: String?
    @State private var lookupTask: Task<Void, Never>?

    private var matches: [Food] {
        LocalFoodLibrary.search(query, saved: savedFoods.filter { !$0.isExpired(at: Date()) }.compactMap(\.food))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Picker("How to add food", selection: $mode) {
                        ForEach(FoodEntryMode.allCases) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented)
                    if mode == .search {
                        Text("Pick a food.").font(.title.bold())
                        Text("Simple staples and your saved foods.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        TextField("Search foods", text: $query)
                            .textFieldStyle(.roundedBorder).autocorrectionDisabled()
                            .accessibilityIdentifier("localFoodSearch")
                        if let error = LocalFoodLibrary.errorMessage {
                            Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                        }
                        if matches.isEmpty {
                            Text("No matches. Scan a barcode or tap Manual to add your own.")
                                .foregroundStyle(.secondary)
                        }
                        LazyVStack(spacing: 10) {
                            ForEach(matches) { food in
                                Button { cacheWarning = nil; selectedFood = food } label: {
                                    FoodSearchRow(food: food)
                                }.buttonStyle(TallyPressStyle())
                            }
                        }
                    } else {
                        barcodeContent
                    }
                    if loading {
                        HStack {
                            ProgressView("Looking up barcode…")
                            Spacer()
                            Button("Cancel") { lookupTask?.cancel(); loading = false }
                        }
                    }
                    if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
                    Text("Scanned products stay on your phone for three months after you last log them. Custom foods stay until you delete them.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(22).frame(maxWidth: 640).frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(MacroTheme.background)
            .navigationTitle("Add Food").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Manual") { manualNutrition = nil; showingManual = true }
                }
            }
            .navigationDestination(item: $selectedFood) { food in
                FoodDetailView(food: food, date: initialDate, followsToday: followsToday, cacheWarning: cacheWarning,
                               onAdded: { date in feedback.added(on: date); dismiss() }, onManual: { manualNutrition = $0; showingManual = true })
            }
            .fullScreenCover(isPresented: $showingScanner, onDismiss: {
                if let code = pendingBarcode {
                    pendingBarcode = nil
                    barcode = code
                    isUPCE = false
                    startLookup()
                }
            }) { BarcodeScannerView { pendingBarcode = $0 } }
            .sheet(isPresented: $showingManual) {
                AddEditEntryView(initialDate: DiaryDates.entryDate(selectedDate: initialDate, followsToday: followsToday),
                                 initialBarcode: selectedFood?.isBuiltIn == true ? nil : (selectedFood?.barcode ?? (mode == .barcode ? lookupBarcode : nil)),
                                 initialName: selectedFood?.name ?? query,
                                 onSaved: { dismiss() }, initialNutrition: manualNutrition)
                    .tallySheet()
            }
            .onChange(of: mode) { _, _ in
                lookupTask?.cancel()
                loading = false
                errorMessage = nil
            }
            .task {
                guard !started else { return }
                started = true
                mode = initialMode
                if let startingFood { selectedFood = startingFood }
                else if let startingBarcode { barcode = startingBarcode; startLookup() }
                else if initialMode == .barcode { showingScanner = true }
            }
            .onDisappear { lookupTask?.cancel() }
        }
    }

    private var barcodeContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Scan once. Keep it here.").font(.title.bold())
            Text("Saved barcodes load from your phone. New barcodes need an internet connection.")
                .font(.subheadline).foregroundStyle(.secondary)
            Button { showingScanner = true } label: {
                Label("Open scanner", systemImage: "barcode.viewfinder").frame(maxWidth: .infinity)
            }.buttonStyle(.borderedProminent).disabled(loading)
            TextField("8, 12, or 13 digit barcode", text: $barcode)
                .keyboardType(.numberPad).textFieldStyle(.roundedBorder)
            Toggle("UPC-E barcode", isOn: $isUPCE)
            Text("Enable only for a compressed 8-digit UPC-E code.").font(.caption).foregroundStyle(.secondary)
            Button("Look up food") { startLookup() }.buttonStyle(.bordered).disabled(loading || barcode.isEmpty)
            Button("Refresh this barcode online") { startLookup(refresh: true) }
                .font(.footnote).disabled(loading || barcode.isEmpty)
        }
    }

    private var lookupBarcode: String? {
        let code = barcode.trimmingCharacters(in: .whitespacesAndNewlines)
        return isUPCE ? FoodBarcode.expandUPCE(code) : (try? FoodBarcode.validated(code))
    }

    private func startLookup(refresh: Bool = false) {
        guard !loading else { return }
        guard let code = lookupBarcode else { errorMessage = FoodAPIError.invalidBarcode.localizedDescription; return }
        loading = true
        errorMessage = nil
        lookupTask = Task { @MainActor in
            defer { if !Task.isCancelled { loading = false } }
            do {
                let result = try await FoodStore(container: modelContext.container).lookup(code, refresh: refresh)
                try Task.checkCancellation()
                cacheWarning = result.warning
                selectedFood = result.food
            } catch is CancellationError { }
            catch { if !Task.isCancelled { errorMessage = error.localizedDescription } }
        }
    }
}

struct FoodSearchRow: View {
    let food: Food
    var body: some View {
        HStack(spacing: 14) {
            FoodIconView(emoji: food.cartoonIcon)
            VStack(alignment: .leading, spacing: 5) {
                Text(food.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                Text(food.subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()).tallyPanel()
    }
}

struct FoodLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedFood.lastUsedAt, order: .reverse) private var savedFoods: [SavedFood]
    @State private var query = ""
    @State private var selectedFood: Food?
    @State private var foodToDelete: SavedFood?
    @State private var saveError: String?
    let onSearch: () -> Void

    private var activeFoods: [SavedFood] { savedFoods.filter { !$0.isExpired(at: Date()) } }
    private var matches: [Food] { LocalFoodLibrary.search(query, saved: activeFoods.compactMap(\.food)) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Common foods are built in. Scanned foods expire after three months without logging; custom foods stay until deleted.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if let error = LocalFoodLibrary.errorMessage { Text(error).foregroundStyle(.orange) }
                }
                Section("On your phone · \(matches.count) foods") {
                    ForEach(matches) { food in
                        Button { selectedFood = food } label: {
                            HStack(spacing: 14) {
                                FoodIconView(emoji: food.cartoonIcon)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(food.name).foregroundStyle(.primary)
                                    Text(food.subtitle).font(.caption).foregroundStyle(.secondary)
                                }
                            }.padding(.vertical, 4)
                        }
                        .swipeActions {
                            if let saved = activeFoods.first(where: { $0.barcode == food.barcode }) {
                                Button("Delete", role: .destructive) { foodToDelete = saved }
                            }
                        }
                    }
                    if matches.isEmpty { Text("No matches. Add a custom food or scan a barcode.") }
                }
                Section {
                    Link("Common food data: USDA FoodData Central", destination: URL(string: "https://fdc.nal.usda.gov/")!)
                    Text("SR Legacy (2018) · Public domain / CC0").font(.caption).foregroundStyle(.secondary)
                }
                FoodAttribution()
            }
            .tallyFormStyle().navigationTitle("Your foods")
            .searchable(text: $query, prompt: "Search offline foods")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Add food", systemImage: "plus", action: onSearch) } }
            .sheet(item: $selectedFood) { food in
                FoodEntryView(initialDate: Date(), startingFood: food).tallySheet()
            }
            .confirmationDialog("Delete this saved food? Your diary entries will stay.",
                                isPresented: Binding(get: { foodToDelete != nil }, set: { if !$0 { foodToDelete = nil } })) {
                Button("Delete food", role: .destructive) {
                    if let saved = foodToDelete {
                        modelContext.delete(saved)
                        do { try modelContext.save() }
                        catch { modelContext.rollback(); saveError = error.localizedDescription }
                    }
                    foodToDelete = nil
                }
            }
            .alert("Could Not Save", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
                Button("OK", role: .cancel) { }
            } message: { Text(saveError ?? "") }
        }
    }
}

struct FoodIconView: View {
    let emoji: String

    var body: some View {
        Text(emoji)
            .font(.system(size: 30))
            .frame(width: 54, height: 54)
            .background(MacroTheme.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
            .accessibilityHidden(true)
    }
}
