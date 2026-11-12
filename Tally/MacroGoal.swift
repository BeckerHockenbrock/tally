import Foundation
import SwiftData

@Model
final class MacroGoal {
    var id: UUID
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var updatedAt: Date
    
    init(
        id: UUID = UUID(),
        calories: Double = 2000,
        protein: Double = 140,
        carbs: Double = 200,
        fat: Double = 65,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.updatedAt = updatedAt
    }
    
    /// Calories calculated directly from the macro goals (4/4/9)
    var calculatedCalories: Double {
        (protein * 4.0) + (carbs * 4.0) + (fat * 9.0)
    }
}

/// Parse editing values without silently replacing malformed input with zero.
enum GoalInput {
    static func value(_ text: String, calories: Bool = false) -> Double? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(cleaned), value.isFinite else { return nil }
        if calories { return (100...1_000_000).contains(value) ? value : nil }
        return value == 0 || (0.1...100_000).contains(value) ? value : nil
    }

    static func editingText(_ value: Double) -> String { String(value) }
}
