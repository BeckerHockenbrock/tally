import SwiftUI

struct NutrientDetailsView: View {
    let entries: [MacroEntry]
    var body: some View {
        List {
            Section {
                Text("Totals include only reported values. Unknown nutrients are never counted as zero. Partial means some diary entries have no value for that nutrient.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Section("Vitamins, minerals & more") {
                ForEach(NutritionTotals.calculate(entries: entries)) { total in
                    LabeledContent {
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(nutrientText(total.amount, unit: total.unit))
                            if total.amount != nil && !total.isComplete {
                                Text("Partial · \(total.knownEntries)/\(total.entryCount) entries")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    } label: { Text(total.name) }
                }
            }
        }
        .tallyFormStyle().navigationTitle("Nutrients").navigationBarTitleDisplayMode(.inline)
    }
}

struct FoodNutrientsSection: View {
    let nutrition: FoodNutrition?
    var body: some View {
        Section {
            DisclosureGroup("Vitamins, minerals & more") {
                ForEach(NutrientDefinition.including(nutrition?.nutrients ?? [:])) { definition in
                    let value = nutrition?.nutrients?[definition.id]
                    LabeledContent(definition.name, value: nutrientText(value?.amount, unit: value?.unit ?? definition.unit))
                }
            }
            Text("Unknown means the source did not report a value. It does not mean zero.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

func nutrientText(_ amount: Double?, unit: String) -> String {
    guard let amount else { return "Unknown" }
    return amount.formatted(.number.precision(.fractionLength(0...3))) + " " + unit
}
