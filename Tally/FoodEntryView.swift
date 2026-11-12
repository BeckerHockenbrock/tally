import SwiftUI
import SwiftData

struct FoodEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedFood.lastUsedAt, order: .reverse) private var recentFoods: [SavedFood]
    let initialDate: Date
    var followsToday = true
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

    var body: some View {
        NavigationStack {
            Form {
                Group {
                Section {
                    Button { showingScanner = true } label: {
                        Label("Scan Barcode", systemImage: "barcode.viewfinder")
                            .font(MacroTheme.bodyFont).frame(maxWidth: .infinity).padding(.vertical, 8)
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.borderedProminent).tint(MacroTheme.accent)
                    .disabled(loading)
                    Button("Enter Food Manually") { showingManual = true }
                }
                Section {
                    TextField("8, 12, or 13 digits", text: $barcode).keyboardType(.numberPad)
                    Toggle("This is a UPC-E barcode", isOn: $isUPCE)
                    Text("For an 8-digit code, select UPC-E only if the package uses UPC-E rather than EAN-8.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Look Up Food") { startLookup() }.disabled(loading || barcode.isEmpty)
                    if loading {
                        ProgressView("Looking up food…")
                        Button("Cancel Lookup") {
                            lookupID = UUID()
                            lookupTask?.cancel()
                            loading = false
                        }
                    }
                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.red)
                        Button("Retry") { startLookup() }.disabled(loading)
                        Button("Enter Nutrition Manually") { showingManual = true }
                    }
                } header: { TallySectionLabel(text: "Enter a Barcode") }
                Section {
                    if recentFoods.isEmpty {
                        Text("Scanned foods will appear here for quick reuse.").foregroundStyle(.secondary)
                    }
                    ForEach(Array(recentFoods.prefix(30))) { saved in
                        VStack(alignment: .leading, spacing: 6) {
                            Button(saved.name) {
                                barcode = saved.barcode
                                isUPCE = false
                                startLookup()
                            }.disabled(loading)
                            Text("Saved \(saved.fetchedAt.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption).foregroundStyle(.secondary)
                            Button("Refresh from Open Food Facts") {
                                barcode = saved.barcode
                                isUPCE = false
                                startLookup(refresh: true)
                            }.font(.caption).disabled(loading)
                        }
                    }
                } header: { TallySectionLabel(text: "Recent Foods") }
                FoodAttribution()

                }
                .listRowBackground(MacroTheme.surface)
            }
            .tallyFormStyle()
            .navigationTitle("Add Food")
            .navigationBarTitleDisplayMode(.inline)

            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .navigationDestination(item: $selectedFood) { food in
                FoodDetailView(food: food, date: initialDate, followsToday: followsToday, cacheWarning: cacheWarning, onAdded: { dismiss() },
                               onManual: { showingManual = true })
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
                                 initialName: selectedFood?.name ?? "",
                                 onSaved: { dismiss() })
                    .tallySheet()
            }
            .onDisappear { lookupTask?.cancel() }
        }
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
                cacheWarning = result.warning
                selectedFood = result.food
            } catch is CancellationError {
                // Closing or cancelling the flow must not present a stale result.
            } catch { errorMessage = error.localizedDescription }
        }
    }
}
