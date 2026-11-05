import Foundation
import SwiftData

@Model
final class MacroEntry {
    var id: UUID
    var name: String
    var protein: Double
    var carbs: Double
    var fat: Double
    var date: Date
    
    init(
        id: UUID = UUID(),
        name: String = "",
        protein: Double = 0,
        carbs: Double = 0,
        fat: Double = 0,
        date: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.date = date
    }
    
    /// Calories calculated according to standard nutritional formula:
    /// Protein: 4 kcal/g, Carbs: 4 kcal/g, Fat: 9 kcal/g
    var calories: Double {
        (protein * 4.0) + (carbs * 4.0) + (fat * 9.0)
    }
    
    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Quick Entry" : trimmed
    }
}
