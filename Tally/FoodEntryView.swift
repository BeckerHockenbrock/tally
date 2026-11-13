import SwiftUI
import SwiftData

enum FoodEntryMode: String, CaseIterable, Identifiable {
    case search, barcode
    var id: String { rawValue }
    var title: String { self == .search ? "Search" : "Barcode" }
}

struct FoodEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedFood.lastUsedAt, order: .reverse) private var recentFoods: [SavedFood]
    let initialDate: Date
    var followsToday = true
    var initialMode = FoodEntryMode.search
    var startingBarcode: String?
    @State private var mode = FoodEntryMode.search
    @State private var started = false
    @State private var cacheWarning: String?
    @State private var barcode = ""
    @State private var isUPCE = false
    @State private var showingScanner = false
    @State private var showingManual = false
    @State private var pendingBarcode: String?
    @State private var selectedFood: Food?
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var lookupID = UUID()
    @State private var lookupTask: Task<Void, Never>?
    @State private var searchText = ""
    @State private var searchResults: [FoodSearchResult] = []
    @State private var searching = false
    @State private var searched = false
    @State private var submittedQuery: String?
    @State private var searchError: String?
    @State private var searchID = UUID()
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Picker("How to add food", selection: $mode) {
                        ForEach(FoodEntryMode.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    if mode == .search {
                        searchHeader
                        searchField
                        lookupStatus
                        searchContent
                        savedFoods
                    } else {
                        barcodeContent
                        lookupStatus
                    }
                    manualEntry
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 10) { FoodAttribution() }
                            .padding(.top, 12)
                    } label: {
                        Label("Food data & credits", systemImage: "info.circle")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .tint(.secondary)
                }
                .padding(22)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(MacroTheme.background)
            .navigationTitle("Add Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .navigationDestination(item: $selectedFood) { food in
                FoodDetailView(food: food, date: initialDate, followsToday: followsToday, cacheWarning: cacheWarning,
                               onAdded: { dismiss() }, onManual: { showingManual = true })
            }
            .fullScreenCover(isPresented: $showingScanner, onDismiss: {
                if let code = pendingBarcode {
                    pendingBarcode = nil
                    barcode = code
                    isUPCE = false
                    startLookup()
                }
            }) {
                BarcodeScannerView { pendingBarcode = $0 }
            }
            .sheet(isPresented: $showingManual) {
                AddEditEntryView(initialDate: DiaryDates.entryDate(selectedDate: initialDate, followsToday: followsToday),
                                 initialBarcode: selectedFood?.barcode ?? lookupBarcode,
                                 initialName: selectedFood?.name ?? trimmedSearch,
                                 onSaved: { dismiss() })
                    .tallySheet()
            }
            .onChange(of: searchText) { _, _ in
                if trimmedSearch != submittedQuery { resetSearch() }
            }
            .onChange(of: mode) { _, _ in
                searchFocused = false
                cancelLookup()
                resetSearch()
                errorMessage = nil
            }
            .task {
                guard !started else { return }
                started = true
                mode = initialMode
                if let startingBarcode {
                    barcode = startingBarcode
                    startLookup()
                } else if initialMode == .barcode {
                    showingScanner = true
                }
            }
            .onDisappear {
                cancelLookup()
                searchTask?.cancel()
                searchID = UUID()
                searching = false
            }
        }
    }

    private var trimmedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var matchingSavedFoods: [SavedFood] {
        if trimmedSearch.isEmpty { return Array(recentFoods.prefix(5)) }
        return recentFoods.filter {
            $0.name.localizedStandardContains(trimmedSearch)
                || ($0.food?.brand?.localizedStandardContains(trimmedSearch) == true)
        }
    }

    private var searchHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("FOOD SEARCH", systemImage: "fork.knife.circle.fill")
                .font(.caption.weight(.semibold)).tracking(1.4)
                .foregroundStyle(MacroTheme.accent)
            Text("What’s on\nyour plate?")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .tracking(-0.8)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text("Find your food. Choose a portion. Make it count.")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.title3).foregroundStyle(MacroTheme.accent)
            TextField("Food name or brand", text: $searchText)
                .focused($searchFocused)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { startSearch() }
                .accessibilityLabel("Food name or brand")
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Clear food search")
            }
            Button { startSearch() } label: {
                Image(systemName: "arrow.right")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(MacroTheme.accent.gradient, in: RoundedRectangle(cornerRadius: 14))
            }
            .disabled(trimmedSearch.isEmpty || searching || loading)
            .accessibilityLabel("Search foods")
        }
        .buttonStyle(TallyPressStyle())
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(MacroTheme.surface, in: RoundedRectangle(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(searchFocused ? MacroTheme.accent : MacroTheme.line.opacity(0.3), lineWidth: 1)
        }
    }

    @ViewBuilder private var searchContent: some View {
        if searching {
            VStack(spacing: 14) {
                ProgressView().controlSize(.large).tint(MacroTheme.accent)
                Text("Finding your food…").font(.headline)
                Button("Cancel search") { resetSearch() }.font(.subheadline)
            }
            .frame(maxWidth: .infinity).padding(28).tallyPanel()
        } else if let searchError {
            FoodSearchMessage(icon: "wifi.exclamationmark", title: "Couldn’t search right now", message: searchError)
            Button("Try again") { startSearch() }
                .buttonStyle(.borderedProminent).disabled(loading)
        } else if searched {
            if searchResults.isEmpty {
                FoodSearchMessage(icon: "magnifyingglass", title: "No matches this time",
                                  message: "Try a different food name or brand, or scan the package barcode.")
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    sectionHeading("Search results", detail: "\(searchResults.count) found")
                    Label("Most popular first", systemImage: "arrow.down")
                        .font(.caption).foregroundStyle(.secondary)
                    LazyVStack(spacing: 10) {
                        ForEach(searchResults) { result in
                            Button { chooseBarcode(result.barcode) } label: {
                                FoodSearchRow(name: result.name, subtitle: result.brand ?? "Open Food Facts",
                                              imageURL: result.imageURL)
                            }
                            .buttonStyle(TallyPressStyle()).disabled(loading)
                        }
                    }
                    Text("Up to 25 matches. Add a brand to narrow your search.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        } else if trimmedSearch.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("A LITTLE INSPIRATION").font(.caption.weight(.semibold))
                    .tracking(1.2).foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    suggestion("Greek yogurt", icon: "sun.max")
                    suggestion("Oats", icon: "leaf")
                    suggestion("Chicken", icon: "fork.knife")
                    suggestion("Peanut butter", icon: "takeoutbag.and.cup.and.straw")
                }
            }
        } else {
            Text("Tap the arrow or Search on your keyboard to find foods.")
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private func suggestion(_ query: String, icon: String) -> some View {
        Button { startSearch(query: query) } label: {
            HStack(spacing: 8) {
                Image(systemName: icon).foregroundStyle(MacroTheme.accent)
                Text(query).foregroundStyle(.primary).font(.subheadline.weight(.medium))
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background(MacroTheme.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(TallyPressStyle()).disabled(loading)
    }

    @ViewBuilder private var savedFoods: some View {
        if !matchingSavedFoods.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                sectionHeading(trimmedSearch.isEmpty ? "Recently used" : "From your foods", detail: "Saved")
                LazyVStack(spacing: 10) {
                    ForEach(matchingSavedFoods) { saved in
                        Button { chooseBarcode(saved.barcode) } label: {
                            FoodSearchRow(name: saved.name, subtitle: saved.food?.brand ?? "Saved for next time",
                                          imageURL: saved.food?.imageURL)
                        }
                        .buttonStyle(TallyPressStyle()).disabled(loading)
                        .contextMenu {
                            Button("Refresh nutrition", systemImage: "arrow.clockwise") {
                                chooseBarcode(saved.barcode, refresh: true)
                            }
                        }
                    }
                }
            }
        }
    }

    private func sectionHeading(_ title: String, detail: String) -> some View {
        HStack {
            Text(title).font(.headline).accessibilityAddTraits(.isHeader)
            Spacer()
            Text(detail).font(.caption.weight(.medium)).foregroundStyle(.secondary)
        }
    }

    private var barcodeContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
                Label("BARCODE SCANNER", systemImage: "barcode.viewfinder")
                    .font(.caption.weight(.semibold)).tracking(1.4).foregroundStyle(MacroTheme.accent)
                Text("Scan your food.")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold)).tracking(-0.8)
                Text("A quick scan brings the package’s nutrition to your diary.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            VStack(spacing: 18) {
                Image(systemName: "barcode.viewfinder")
                    .font(.system(size: 70, weight: .light))
                    .foregroundStyle(MacroTheme.accent)
                    .accessibilityHidden(true)
                Text("Point. Scan. You’re ready.").font(.headline)
                Button { showingScanner = true } label: {
                    Label("Open scanner", systemImage: "camera")
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent).buttonBorderShape(.capsule).disabled(loading)
            }
            .padding(24).frame(maxWidth: .infinity)
            .background(MacroTheme.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 24))
            VStack(alignment: .leading, spacing: 16) {
                Text("Or type the barcode").font(.headline)
                TextField("8, 12, or 13 digits", text: $barcode)
                    .keyboardType(.numberPad).padding(14)
                    .background(MacroTheme.background, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel("Product barcode")
                Toggle("UPC-E barcode", isOn: $isUPCE).font(.subheadline)
                Text("For an 8-digit code, enable this only when the package uses UPC-E instead of EAN-8.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Look up food") { startLookup() }
                    .buttonStyle(.borderedProminent)
                    .disabled(loading || barcode.isEmpty)
            }
            .padding(20).tallyPanel()
        }
    }

    @ViewBuilder private var lookupStatus: some View {
        if loading {
            HStack(spacing: 12) {
                ProgressView()
                Text("Loading nutrition…").font(.subheadline)
                Spacer(minLength: 0)
                Button("Cancel") { cancelLookup() }.font(.subheadline)
            }
            .padding(18).tallyPanel()
        } else if let errorMessage {
            FoodSearchMessage(icon: "exclamationmark.circle", title: "Couldn’t load this food", message: errorMessage)
            Button("Retry lookup") { startLookup() }.buttonStyle(.bordered)
        }
    }

    private var manualEntry: some View {
        Button { showingManual = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "square.and.pencil").font(.title3).foregroundStyle(MacroTheme.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Add it yourself").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    Text("Enter a meal or nutrition manually").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            .padding(18).tallyPanel()
        }
        .buttonStyle(TallyPressStyle())
    }

    private func chooseBarcode(_ code: String, refresh: Bool = false) {
        guard !loading else { return }
        searchFocused = false
        barcode = code
        isUPCE = false
        startLookup(refresh: refresh)
    }

    private func resetSearch() {
        searchTask?.cancel()
        searchID = UUID()
        searching = false
        searched = false
        submittedQuery = nil
        searchResults = []
        searchError = nil
    }

    private func startSearch(query: String? = nil) {
        let query = (query ?? trimmedSearch).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, !searching, !loading else { return }
        resetSearch()
        searchText = query
        submittedQuery = query
        searchFocused = false
        searching = true
        let id = searchID
        searchTask = Task { @MainActor in
            defer { if searchID == id { searching = false } }
            do {
                let results = try await FoodAPIService.shared.search(query: query)
                try Task.checkCancellation()
                guard searchID == id else { return }
                searchResults = results
                searched = true
            } catch is CancellationError {
                // Editing or closing the search discards its pending response.
            } catch {
                guard searchID == id else { return }
                searchError = error.localizedDescription
            }
        }
    }

    private func cancelLookup() {
        lookupID = UUID()
        lookupTask?.cancel()
        loading = false
    }

    private var lookupBarcode: String? {
        let input = barcode.trimmingCharacters(in: .whitespacesAndNewlines)
        if isUPCE { return FoodBarcode.expandUPCE(input) }
        return try? FoodBarcode.validated(input)
    }

    private func startLookup(refresh: Bool = false) {
        guard !loading else { return }
        guard let code = lookupBarcode else {
            errorMessage = FoodAPIError.invalidBarcode.localizedDescription
            return
        }
        loading = true
        errorMessage = nil
        let id = UUID()
        lookupID = id
        lookupTask = Task { @MainActor in
            defer { if lookupID == id { loading = false } }
            do {
                let result = try await FoodStore(container: modelContext.container).lookup(code, refresh: refresh)
                try Task.checkCancellation()
                guard lookupID == id else { return }
                cacheWarning = result.warning
                selectedFood = result.food
            } catch is CancellationError {
                // Closing or cancelling the flow must not present a stale result.
            } catch {
                guard lookupID == id else { return }
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct FoodSearchRow: View {
    let name: String
    let subtitle: String
    let imageURL: URL?

    var body: some View {
        HStack(spacing: 14) {
            AsyncImage(url: imageURL) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    Image(systemName: "fork.knife")
                        .font(.title3).foregroundStyle(MacroTheme.accent)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(MacroTheme.accent.opacity(0.07))
                }
            }
            .frame(width: 54, height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if !subtitle.isEmpty {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .tallyPanel()
    }
}

private struct FoodSearchMessage: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.largeTitle).foregroundStyle(MacroTheme.accent)
            Text(title).font(.headline)
            Text(message).font(.subheadline).foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity).padding(24).tallyPanel()
    }
}

struct FoodLibraryView: View {
    @Query(sort: \SavedFood.lastUsedAt, order: .reverse) private var foods: [SavedFood]
    @State private var query = ""
    @State private var selectedFood: SavedFood?
    let onSearch: () -> Void

    private var matchingFoods: [SavedFood] {
        let terms = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !terms.isEmpty else { return foods }
        return foods.filter {
            $0.name.localizedStandardContains(terms) || $0.food?.brand?.localizedStandardContains(terms) == true
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if foods.isEmpty {
                        FoodSearchMessage(icon: "fork.knife.circle", title: "Your go-to foods, together.",
                                          message: "Foods you look up are saved here, ready for next time.")
                        Button("Find a food", action: onSearch).buttonStyle(.borderedProminent)
                    } else {
                        HStack {
                            Text("Ready for another serving.").font(.subheadline).foregroundStyle(.secondary)
                            Spacer()
                            Text("\(foods.count) saved").font(.caption.weight(.semibold)).foregroundStyle(MacroTheme.accent)
                        }
                        if matchingFoods.isEmpty {
                            FoodSearchMessage(icon: "magnifyingglass", title: "No saved matches",
                                              message: "Try a different name or find something new with food search.")
                            Button("Search all foods", action: onSearch).buttonStyle(.borderedProminent)
                        }
                        LazyVStack(spacing: 10) {
                            ForEach(matchingFoods) { saved in
                                Button { selectedFood = saved } label: {
                                    FoodSearchRow(name: saved.name,
                                                  subtitle: saved.food?.brand ?? "Saved \(saved.fetchedAt.formatted(date: .abbreviated, time: .omitted))",
                                                  imageURL: saved.food?.imageURL)
                                }
                                .buttonStyle(TallyPressStyle())
                            }
                        }
                    }
                }
                .padding(22).frame(maxWidth: 640).frame(maxWidth: .infinity)
            }
            .background(MacroTheme.background)
            .navigationTitle("Your foods")
            .searchable(text: $query, prompt: "Search your saved foods")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Find food", systemImage: "magnifyingglass", action: onSearch)
                }
            }
            .sheet(item: $selectedFood) { food in
                FoodEntryView(initialDate: Date(), startingBarcode: food.barcode).tallySheet()
            }
        }
    }
}
