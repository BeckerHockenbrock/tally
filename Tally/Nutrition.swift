import Foundation

/// Amounts always carry their unit and source; absence means unknown, never zero.
struct NutrientAmount: Codable, Hashable {
    let name: String
    let unit: String
    var amount: Double
    var source: String?
}

struct NutrientDefinition: Identifiable {
    let id: String
    let name: String
    let unit: String

    static let common: [NutrientDefinition] = [
        .init(id: "fiber", name: "Fiber", unit: "g"),
        .init(id: "sugars", name: "Total sugars", unit: "g"),
        .init(id: "added-sugars", name: "Added sugars", unit: "g"),
        .init(id: "saturated-fat", name: "Saturated fat", unit: "g"),
        .init(id: "trans-fat", name: "Trans fat", unit: "g"),
        .init(id: "monounsaturated-fat", name: "Monounsaturated fat", unit: "g"),
        .init(id: "polyunsaturated-fat", name: "Polyunsaturated fat", unit: "g"),
        .init(id: "cholesterol", name: "Cholesterol", unit: "mg"),
        .init(id: "sodium", name: "Sodium", unit: "mg"),
        .init(id: "potassium", name: "Potassium", unit: "mg"),
        .init(id: "calcium", name: "Calcium", unit: "mg"),
        .init(id: "iron", name: "Iron", unit: "mg"),
        .init(id: "magnesium", name: "Magnesium", unit: "mg"),
        .init(id: "phosphorus", name: "Phosphorus", unit: "mg"),
        .init(id: "zinc", name: "Zinc", unit: "mg"),
        .init(id: "copper", name: "Copper", unit: "mg"),
        .init(id: "manganese", name: "Manganese", unit: "mg"),
        .init(id: "selenium", name: "Selenium", unit: "µg"),
        .init(id: "iodine", name: "Iodine", unit: "µg"),
        .init(id: "chromium", name: "Chromium", unit: "µg"),
        .init(id: "molybdenum", name: "Molybdenum", unit: "µg"),
        .init(id: "chloride", name: "Chloride", unit: "mg"),
        // RAE and DFE are distinct from unqualified vitamin A and folate.
        .init(id: "vitamin-a-rae", name: "Vitamin A (RAE)", unit: "µg"),
        .init(id: "vitamin-a", name: "Vitamin A (label)", unit: "µg"),
        .init(id: "vitamin-c", name: "Vitamin C", unit: "mg"),
        .init(id: "vitamin-d", name: "Vitamin D", unit: "µg"),
        .init(id: "vitamin-e", name: "Vitamin E", unit: "mg"),
        .init(id: "vitamin-k", name: "Vitamin K", unit: "µg"),
        .init(id: "vitamin-b1", name: "Thiamin (B1)", unit: "mg"),
        .init(id: "vitamin-b2", name: "Riboflavin (B2)", unit: "mg"),
        .init(id: "vitamin-pp", name: "Niacin (B3)", unit: "mg"),
        .init(id: "pantothenic-acid", name: "Pantothenic acid (B5)", unit: "mg"),
        .init(id: "vitamin-b6", name: "Vitamin B6", unit: "mg"),
        .init(id: "biotin", name: "Biotin (B7)", unit: "µg"),
        .init(id: "folates", name: "Folate (total)", unit: "µg"),
        .init(id: "folate-dfe", name: "Folate (DFE)", unit: "µg"),
        .init(id: "folic-acid", name: "Folic acid", unit: "µg"),
        .init(id: "vitamin-b12", name: "Vitamin B12", unit: "µg"),
        .init(id: "choline", name: "Choline", unit: "mg")
    ]

    static func including(_ values: [String: NutrientAmount]) -> [NutrientDefinition] {
        let known = Set(common.map(\.id))
        let other = values.filter { !known.contains($0.key) }.map {
            NutrientDefinition(id: $0.key, name: $0.value.name, unit: $0.value.unit)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return common + other
    }
}

struct NutrientTotal: Identifiable {
    let id: String
    let name: String
    let unit: String
    var amount: Double?
    var knownEntries: Int
    let entryCount: Int
    var isComplete: Bool { knownEntries == entryCount }
}

enum NutritionTotals {
    static func calculate(entries: [MacroEntry]) -> [NutrientTotal] {
        let snapshots = entries.map { $0.nutrition.nutrients ?? [:] }
        let definitions = snapshots.reduce(into: [String: NutrientAmount]()) { result, values in
            result.merge(values) { first, _ in first }
        }
        return NutrientDefinition.including(definitions).map { definition in
            var sum = 0.0
            var known = 0
            for snapshot in snapshots {
                if let value = snapshot[definition.id], value.unit == definition.unit,
                   value.amount.isFinite, value.amount >= 0 {
                    sum += value.amount
                    known += 1
                }
            }
            return NutrientTotal(id: definition.id, name: definition.name, unit: definition.unit,
                                 amount: known == 0 ? nil : sum, knownEntries: known, entryCount: entries.count)
        }
    }
}
