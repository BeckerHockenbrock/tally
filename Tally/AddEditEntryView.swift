import SwiftUI
import SwiftData

struct AddEditEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var feedback: TallyFeedback
    @Environment(\.modelContext) private var modelContext

    var entryToEdit: MacroEntry?
    var initialDate: Date
    var initialBarcode: String?
    var initialName: String
    var onSaved: (() -> Void)?
    var initialNutrition: FoodNutrition?
    @State private var caloriesText = ""
    @State private var saveError: String?
    @State private var initialized = false
    @State private var nutrientTexts: [String: String] = [:]
    @State private var originalNutrients: [String: NutrientAmount] = [:]
    @State private var saveToFoods = false

    private var nutrientDefinitions: [NutrientDefinition] { NutrientDefinition.including(originalNutrients) }

    private var enteredNutrients: [String: NutrientAmount] {
        var result: [String: NutrientAmount] = [:]
        for definition in nutrientDefinitions {
            guard let text = nutrientTexts[definition.id], !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let value = parseInput(text)
            if let original = originalNutrients[definition.id], original.amount == value {
                result[definition.id] = original
            } else {
                result[definition.id] = NutrientAmount(name: definition.name, unit: definition.unit, amount: value, source: "Manual")
            }
        }
        return result
    }

    @State private var name: String = ""
    @State private var proteinText: String = ""
    @State private var carbsText: String = ""
    @State private var fatText: String = ""
    @State private var entryDate: Date = Date()
    @State private var isShowingDeleteConfirm: Bool = false
    @FocusState private var focusedField: Field?

    enum Field: Hashable {
        case name, protein, carbs, fat
    }

    init(entryToEdit: MacroEntry? = nil, initialDate: Date = Date(), initialBarcode: String? = nil,
         initialName: String = "", onSaved: (() -> Void)? = nil, initialNutrition: FoodNutrition? = nil) {
        self.entryToEdit = entryToEdit
        self.initialDate = initialDate
        self.initialBarcode = initialBarcode
        self.initialName = initialName
        self.onSaved = onSaved
        self.initialNutrition = initialNutrition
    }

    private var proteinValue: Double {
        parseInput(proteinText)
    }

    private var carbsValue: Double {
        parseInput(carbsText)
    }

    private var fatValue: Double {
        parseInput(fatText)
    }

    private var calculatedCalories: Double {
        (proteinValue * 4.0) + (carbsValue * 4.0) + (fatValue * 9.0)
    }

    private var isFormValid: Bool {
        let macros = [proteinText, carbsText, fatText]
        let valid = macros.allSatisfy { text in
            text.isEmpty || (Double(text.replacingOccurrences(of: ",", with: ".")).map { $0.isFinite && $0 >= 0 && $0 <= 100_000 } ?? false)
        }
        let energyValid = caloriesText.isEmpty || (Double(caloriesText.replacingOccurrences(of: ",", with: ".")).map {
            $0.isFinite && $0 >= 0 && $0 <= 1_000_000
        } ?? false)
        // Barcode fallback requires explicit values, including explicit zeros.
        let explicit = (initialBarcode == nil || macros.allSatisfy { !$0.isEmpty })
        let nutrientsValid = nutrientTexts.values.allSatisfy { text in
            let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
            return cleaned.isEmpty || (Double(cleaned).map { $0.isFinite && $0 >= 0 && $0 <= 1_000_000_000 } ?? false)
        }
        let namedFood = !saveToFoods || !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return valid && energyValid && explicit && nutrientsValid && namedFood && (proteinValue > 0 || carbsValue > 0 || fatValue > 0 || !caloriesText.isEmpty)
    }

    var body: some View {
        NavigationStack {
            Form {
                Group {
                Section {
                    TextField("Entry name (e.g., Lunch, Protein Shake)", text: $name)
                        .focused($focusedField, equals: .name)

                    DatePicker("Date & Time", selection: $entryDate, displayedComponents: [.date, .hourAndMinute])
                } header: {
                    TallySectionLabel(text: "Details")
                }

                Section {
                    HStack {
                        Label {
                            Text("Protein")
                        } icon: {
                            Image(systemName: "flame.fill")
                                .foregroundStyle(MacroTheme.protein)
                        }
                        Spacer()
                        TextField("0", text: $proteinText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($focusedField, equals: .protein)
                            .frame(maxWidth: 90)
                        Text("g")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Label {
                            Text("Carbs")
                        } icon: {
                            Image(systemName: "bolt.fill")
                                .foregroundStyle(MacroTheme.carbs)
                        }
                        Spacer()
                        TextField("0", text: $carbsText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($focusedField, equals: .carbs)
                            .frame(maxWidth: 90)
                        Text("g")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Label {
                            Text("Fat")
                        } icon: {
                            Image(systemName: "drop.fill")
                                .foregroundStyle(MacroTheme.fat)
                        }
                        Spacer()
                        TextField("0", text: $fatText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($focusedField, equals: .fat)
                            .frame(maxWidth: 90)
                        Text("g")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    TallySectionLabel(text: "Macros (Grams)")
                } footer: {
                    Text("4 cal/g protein • 4 cal/g carbs • 9 cal/g fat")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Total Calories")
                                .font(.headline)
                            Spacer()
                            Text(MacroTheme.formatCalories(calculatedCalories))
                                .font(.largeTitle.weight(.semibold))
                                .foregroundStyle(MacroTheme.calories)
                            Text("kcal")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        // Mini breakdown bar
                        if calculatedCalories > 0 {
                            GeometryReader { proxy in
                                let total = max(1.0, calculatedCalories)
                                let pWidth = proxy.size.width * CGFloat((proteinValue * 4.0) / total)
                                let cWidth = proxy.size.width * CGFloat((carbsValue * 4.0) / total)
                                let fWidth = proxy.size.width * CGFloat((fatValue * 9.0) / total)

                                HStack(spacing: 2) {
                                    if pWidth > 0 {
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(MacroTheme.protein)
                                            .frame(width: max(2, pWidth))
                                    }
                                    if cWidth > 0 {
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(MacroTheme.carbs)
                                            .frame(width: max(2, cWidth))
                                    }
                                    if fWidth > 0 {
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(MacroTheme.fat)
                                            .frame(width: max(2, fWidth))
                                    }
                                }
                            }
                            .frame(height: 8)
                            .clipShape(Capsule())

                            HStack {
                                MacroPill(label: "Protein", calories: proteinValue * 4, color: MacroTheme.protein)
                                Spacer()
                                MacroPill(label: "Carbs", calories: carbsValue * 4, color: MacroTheme.carbs)
                                Spacer()
                                MacroPill(label: "Fat", calories: fatValue * 9, color: MacroTheme.fat)
                            }
                            .font(.caption)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    TallySectionLabel(text: "Estimated Energy from Macros")
                }

                Section {
                    TextField("Calories from label (optional)", text: $caloriesText)
                        .keyboardType(.decimalPad)
                    if let barcode = entryToEdit?.barcode ?? initialBarcode {
                        LabeledContent("Barcode", value: barcode)
                    }
                    if let portion = entryToEdit?.portionDescription {
                        LabeledContent("Logged portion", value: portion)
                    }
                } footer: {
                    Text("Label calories override the macro estimate. When editing nutrition, update calories too or clear this field to use the estimate. For a scanned food, enter every macro, including zero.")
                }

                Section {
                    DisclosureGroup("Vitamins, minerals & more") {
                        ForEach(nutrientDefinitions) { definition in
                            HStack {
                                Text(definition.name)
                                Spacer()
                                TextField("Unknown", text: Binding(
                                    get: { nutrientTexts[definition.id] ?? "" },
                                    set: { nutrientTexts[definition.id] = $0 }))
                                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(maxWidth: 100)
                                    .accessibilityLabel(definition.name)
                                Text(definition.unit).foregroundStyle(.secondary)
                            }
                        }
                    }
                } footer: { Text("Amounts are for this entire diary entry. Leave unavailable values blank; enter 0 only when known.") }

                if entryToEdit == nil {
                    Section {
                        Toggle("Save to my foods", isOn: $saveToFoods)
                        if saveToFoods {
                            Text("This whole entry becomes one serving. Give it a name to reuse it offline.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                if entryToEdit != nil {
                    Section {
                        Button(role: .destructive) {
                            isShowingDeleteConfirm = true
                        } label: {
                            HStack {
                                Spacer()
                                Label("Delete Entry", systemImage: "trash")
                                Spacer()
                            }
                        }
                    }
                }

                }
                .listRowBackground(MacroTheme.surface)
            }
            .tallyFormStyle()
            .navigationTitle(entryToEdit == nil ? "Add Entry" : "Edit Entry")

            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(entryToEdit == nil ? "Save" : "Update") {
                        saveEntry()
                    }
                    .disabled(!isFormValid)
                    .fontWeight(.semibold)
                }

                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        focusedField = nil
                    }
                }
            }
            .confirmationDialog(
                "Delete Entry",
                isPresented: $isShowingDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let entry = entryToEdit {
                        modelContext.delete(entry)
                        do { try modelContext.save() }
                        catch {
                            modelContext.rollback()
                            saveError = error.localizedDescription
                            return
                        }
                    }
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to delete this macro entry?")
            }
            .onAppear {
                guard !initialized else { return }
                initialized = true
                populateInitialData()
            }
            .alert("Could Not Save", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(saveError ?? "") }
        }
    }

    private func parseInput(_ text: String) -> Double {
        let cleaned = text.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(cleaned), value.isFinite, value >= 0 else { return 0 }
        return value
    }

    private func populateInitialData() {
        if let entry = entryToEdit {
            name = entry.name
            caloriesText = entry.energyIsEstimated == true ? "" : (entry.reportedCalories.map { String($0) } ?? "")
            originalNutrients = entry.nutrition.nutrients ?? [:]
            nutrientTexts = originalNutrients.mapValues { String($0.amount) }
            proteinText = String(entry.protein)
            carbsText = String(entry.carbs)
            fatText = String(entry.fat)
            entryDate = entry.date
        } else {
            name = initialName
            saveToFoods = initialBarcode != nil
            if let nutrition = initialNutrition {
                caloriesText = nutrition.energyEstimated ? "" : (nutrition.calories.map(String.init(describing:)) ?? "")
                proteinText = nutrition.protein.map(String.init(describing:)) ?? ""
                carbsText = nutrition.carbs.map(String.init(describing:)) ?? ""
                fatText = nutrition.fat.map(String.init(describing:)) ?? ""
                originalNutrients = nutrition.nutrients ?? [:]
                nutrientTexts = originalNutrients.mapValues { String($0.amount) }
            }
            let calendar = Calendar.current
            if calendar.isDateInToday(initialDate) {
                entryDate = Date()
            } else {
                let nowComponents = calendar.dateComponents([.hour, .minute, .second], from: Date())
                entryDate = calendar.date(bySettingHour: nowComponents.hour ?? 12,
                                         minute: nowComponents.minute ?? 0,
                                         second: nowComponents.second ?? 0,
                                         of: initialDate) ?? initialDate
            }
            focusedField = .name
        }
    }

    private func saveEntry() {
        guard isFormValid else { return }
        let p = proteinValue
        let c = carbsValue
        let f = fatValue
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        let nutrition = FoodNutrition(calories: caloriesText.isEmpty ? calculatedCalories : parseInput(caloriesText),
                                      protein: p, carbs: c, fat: f, energyEstimated: caloriesText.isEmpty,
                                      nutrients: enteredNutrients)
        let entry = entryToEdit ?? MacroEntry()
        if entryToEdit == nil { modelContext.insert(entry) }
        let nutritionChanged = entryToEdit == nil || entry.protein != p || entry.carbs != c || entry.fat != f ||
            (entry.nutrition.nutrients ?? [:]) != enteredNutrients || entry.calories != nutrition.calories
        entry.name = trimmedName
        entry.date = entryDate
        if nutritionChanged {
            entry.portionDescription = nil
            entry.dataSource = entryToEdit == nil ? "Manual" : "Manual edit"
        }
        entry.barcode = entry.barcode ?? initialBarcode

        do {
            try entry.setNutrition(nutrition)
            if entryToEdit == nil && saveToFoods {
                let code = initialBarcode.map(FoodBarcode.cacheKey) ?? "custom:" + UUID().uuidString
                let food = Food(barcode: code, name: trimmedName, brand: nil, imageURL: nil,
                                servingSize: "1 serving = this entry", portions: [FoodPortion(unit: .servings, nutrition: nutrition)], source: "Manual")
                try FoodStore.saveCustom(food, in: modelContext)
                entry.barcode = code
            }
            if entryToEdit == nil, let code = entry.barcode {
                let saved = try modelContext.fetch(FetchDescriptor<SavedFood>(predicate: #Predicate { $0.barcode == code })).first
                saved?.lastUsedAt = Date()
            }
            try modelContext.save()
            if entryToEdit == nil { feedback.added(on: entry.date) }
            else { feedback.confirm("Entry updated") }
            dismiss()
            onSaved?()
        } catch {
            modelContext.rollback()
            saveError = error.localizedDescription
        }
    }
}

private struct MacroPill: View {
    let label: String
    let calories: Double
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .foregroundStyle(.secondary)
            Text("\(MacroTheme.formatCalories(calories)) kcal")
                .foregroundStyle(.primary)
                .fontWeight(.medium)
        }
    }
}
