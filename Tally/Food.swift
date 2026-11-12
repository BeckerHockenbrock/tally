import Foundation

/// Database definitions are values, independent of persisted diary snapshots.
struct Food: Codable, Identifiable, Hashable {
    var id: String { barcode }
    let barcode: String
    let name: String
    let brand: String?
    let imageURL: URL?
    let servingSize: String?
    let portions: [FoodPortion]
}

struct FoodPortion: Codable, Identifiable, Hashable {
    var id: String { unit.rawValue }
    let unit: PortionUnit
    /// Nutrition for one gram, one milliliter, or one serving.
    let nutrition: FoodNutrition
}

enum PortionUnit: String, Codable, CaseIterable, Identifiable {
    case grams, milliliters, servings
    var id: String { rawValue }
    var label: String {
        switch self {
        case .grams: "Grams"
        case .milliliters: "Milliliters"
        case .servings: "Servings"
        }
    }
}

struct FoodNutrition: Codable, Hashable {
    let calories: Double?
    let protein: Double?
    let carbs: Double?
    let fat: Double?
    var energyEstimated = false

    var isComplete: Bool {
        [calories, protein, carbs, fat].allSatisfy { value in
            guard let value else { return false }
            return value.isFinite && value >= 0
        }
    }

    func scaled(by quantity: Double) -> FoodNutrition? {
        guard quantity.isFinite, quantity > 0 else { return nil }
        let values = [calories, protein, carbs, fat].map { $0.map { $0 * quantity } }
        guard values.compactMap({ $0 }).allSatisfy({ $0.isFinite && $0 >= 0 }) else { return nil }
        return FoodNutrition(calories: values[0], protein: values[1], carbs: values[2],
                             fat: values[3], energyEstimated: energyEstimated)
    }
}

enum FoodBarcode {
    static func validated(_ input: String) throws -> String {
        let code = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard [8, 12, 13].contains(code.count),
              code.utf8.allSatisfy({ (48...57).contains($0) }) else {
            throw FoodAPIError.invalidBarcode
        }
        return code
    }

    /// UPC-A and its EAN-13 representation share one cache key. Never parse as an integer.
    static func cacheKey(_ code: String) -> String {
        code.count == 12 ? "0" + code : code
    }

    /// UPC-E is compressed UPC-A, not EAN-8. Only expand when Vision identifies that symbology.
    static func expandUPCE(_ code: String) -> String? {
        let digits = Array(code)
        guard digits.count == 8, digits.allSatisfy({ $0.isASCII && $0.isNumber }),
              digits[0] == "0" || digits[0] == "1" else { return nil }
        let d = Array(digits[1...6])
        let body: String
        switch d[5] {
        case "0", "1", "2":
            body = String(d[0...1]) + String(d[5]) + "0000" + String(d[2...4])
        case "3":
            body = String(d[0...2]) + "00000" + String(d[3...4])
        case "4":
            body = String(d[0...3]) + "00000" + String(d[4])
        default:
            body = String(d[0...4]) + "0000" + String(d[5])
        }
        return String(digits[0]) + body + String(digits[7])
    }
}

/// A one-shot gate shared by scanner callbacks, including repeated didUpdate events.
struct BarcodeScanGate {
    private(set) var accepted = false
    mutating func accept(_ barcode: String) -> Bool {
        guard !accepted, (try? FoodBarcode.validated(barcode)) != nil else { return false }
        accepted = true
        return true
    }
}
