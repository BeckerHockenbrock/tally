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
