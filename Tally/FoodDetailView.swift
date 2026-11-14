import SwiftUI
import SwiftData

struct FoodDetailView: View {
    @Environment(\.modelContext) private var modelContext
    let food: Food
    let date: Date
    let followsToday: Bool
    let cacheWarning: String?
    let onAdded: (Date) -> Void
    let onManual: (FoodNutrition?) -> Void
    @State private var unit: PortionUnit
    @State private var quantityText: String
    @State private var saveError: String?
    @State private var saved = false

    init(food: Food, date: Date, followsToday: Bool = true, cacheWarning: String? = nil, onAdded: @escaping (Date) -> Void, onManual: @escaping (FoodNutrition?) -> Void) {
        self.food = food
        self.date = date
        self.followsToday = followsToday
        self.cacheWarning = cacheWarning
        self.onAdded = onAdded
        self.onManual = onManual
        let initial = food.portions.first?.unit ?? .servings
        _unit = State(initialValue: initial)
        _quantityText = State(initialValue: initial == .servings ? "1" : "100")
    }

    private var quantity: Double? {
        Double(quantityText.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "."))
    }

    private var nutrition: FoodNutrition? {
        guard let quantity else { return nil }
        return food.portions.first { $0.unit == unit }?.nutrition.scaled(by: quantity)
    }

    var body: some View {
        Form {
                Group {
            FoodHeader(food: food)
            if let cacheWarning {
                Section {
                    Label(cacheWarning, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
            if !food.portions.isEmpty {
                Section {
                    Picker("Unit", selection: $unit) {
                        ForEach(food.portions) { portion in
                            Text(portion.unit.label).tag(portion.unit)
                        }
                    }
                    TextField("Quantity", text: $quantityText)
                        .keyboardType(.decimalPad)
                    Text("Enter any positive quantity, including fractional servings.")
                        .font(.caption).foregroundStyle(.secondary)
                    if nutrition == nil {
                        Text("Enter a valid quantity greater than zero.").foregroundStyle(.red)
                    }
                } header: { TallySectionLabel(text: "Your Portion") }
                NutritionSummary(nutrition: nutrition)
                FoodNutrientsSection(nutrition: nutrition)
            }
            if food.portions.isEmpty || nutrition?.isComplete != true {
                Section {
                    Text("Some nutrition information is missing or uses unsupported units. Missing values are not zero. Check the package and enter the nutrition manually.")
                    Button("Enter Nutrition Manually") { onManual(nutrition) }
                }
            }
            Section {
                Button(action: addToDiary) {
                    Label("Add to Diary", systemImage: "plus.circle.fill")
                        .font(MacroTheme.bodyFont).frame(maxWidth: .infinity)
                        .foregroundStyle(.white)
                }
                .buttonStyle(.borderedProminent)
                .tint(MacroTheme.accent)
                .disabled(nutrition?.isComplete != true || saved)
            }
            if food.isBuiltIn {
                Section {
                    Link("Data: USDA FoodData Central · SR Legacy (2018)", destination: URL(string: "https://fdc.nal.usda.gov/food-details/" + String(food.barcode.dropFirst(5)) + "/nutrients")!)
                    Text("Public domain / CC0").font(.caption).foregroundStyle(.secondary)
                }
            } else if !food.isCustom { FoodAttribution(barcode: food.barcode) }

                }
                .listRowBackground(MacroTheme.surface)
            }
            .tallyFormStyle()
        .navigationTitle("Food Details")

        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: unit) { _, newUnit in quantityText = newUnit == .servings ? "1" : "100" }
        .alert("Could Not Save Entry", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(saveError ?? "") }
    }

    private func addToDiary() {
        guard !saved, let nutrition, nutrition.isComplete,
              let calories = nutrition.calories, let protein = nutrition.protein,
              let carbs = nutrition.carbs, let fat = nutrition.fat, let quantity else { return }
        let context = ModelContext(modelContext.container)
        let entry = MacroEntry(name: food.name, protein: protein, carbs: carbs, fat: fat,
                               date: DiaryDates.entryDate(selectedDate: date, followsToday: followsToday))
        entry.reportedCalories = calories
        entry.energyIsEstimated = nutrition.energyEstimated
        entry.barcode = food.barcode
        entry.portionDescription = "\(quantity.formatted()) \(unit.label.lowercased())"
        entry.dataSource = food.sourceName
        context.insert(entry)
        do {
            try entry.setNutrition(nutrition)
            try FoodStore.recordUse(of: food, in: context)
            try context.save()
            saved = true
            onAdded(entry.date)
        } catch { saveError = error.localizedDescription }
    }
}

private struct FoodHeader: View {
    let food: Food
    var body: some View {
        Section {
            HStack(spacing: 14) {
                FoodIconView(emoji: food.cartoonIcon)
                Text(food.name).font(.title2.bold())
            }
            if let brand = food.brand, !brand.isEmpty { Text(brand).foregroundStyle(.secondary) }
            if !food.isBuiltIn && !food.isCustom { LabeledContent("Barcode", value: food.barcode) }
            if let preparation = food.preparation {
                LabeledContent("Weigh it", value: preparation)
            }
            if let serving = food.servingSize { LabeledContent("One serving", value: serving) }
            Text(food.isBuiltIn ? "Use the preparation shown above when weighing your portion." : "Compare scanned products with your package.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct NutritionSummary: View {
    let nutrition: FoodNutrition?
    var body: some View {
        Section {
            NutritionRow(title: "Calories", value: nutrition?.calories, unit: "kcal", color: MacroTheme.calories)
            NutritionRow(title: "Protein", value: nutrition?.protein, unit: "g", color: MacroTheme.protein)
            NutritionRow(title: "Carbohydrates", value: nutrition?.carbs, unit: "g", color: MacroTheme.carbs)
            NutritionRow(title: "Fat", value: nutrition?.fat, unit: "g", color: MacroTheme.fat)
            if nutrition?.energyEstimated == true {
                Text("Energy estimate — database estimate or 4/4/9 calculation.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } header: { TallySectionLabel(text: "Nutrition for Your Portion") }
    }
}

private struct NutritionRow: View {
    let title: String
    let value: Double?
    let unit: String
    let color: Color
    var body: some View {
        LabeledContent(title) {
            Text(value.map { "\($0.formatted(.number.precision(.fractionLength(0...1)))) \(unit)" } ?? "Unknown")
                .foregroundStyle(color)
        }
    }
}

struct FoodAttribution: View {
    var barcode: String?
    var body: some View {
        Section {
            if let url = URL(string: "https://world.openfoodfacts.org" + (barcode.map { "/product/\($0)" } ?? "")) {
                Link("Data: Open Food Facts contributors", destination: url)
            }
            if let url = URL(string: "https://opendatacommons.org/licenses/odbl/1-0/") {
                Link("Database: ODbL 1.0", destination: url)
            }
            if let url = URL(string: "https://opendatacommons.org/licenses/dbcl/1-0/") {
                Link("Contents: Database Contents License", destination: url)
            }
            if let url = URL(string: "https://creativecommons.org/licenses/by-sa/3.0/") {
                Link("Images: CC BY-SA 3.0", destination: url)
            }
        } footer: {
            Text("Community-contributed data may be incomplete. Verify the label before logging.")
        }
        .font(.footnote)
    }
}
