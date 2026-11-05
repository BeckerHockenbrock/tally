import SwiftUI

enum MacroTheme {
    static let calories = Color.orange
    static let protein = Color(red: 0.2, green: 0.55, blue: 0.95) // Vibrant Sky Blue
    static let carbs = Color(red: 0.95, green: 0.65, blue: 0.15) // Amber Gold
    static let fat = Color(red: 0.85, green: 0.35, blue: 0.65) // Rose / Fuchsia
    
    static func formatAmount(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", value)
        } else {
            return String(format: "%.1f", value)
        }
    }
    
    static func formatCalories(_ value: Double) -> String {
        String(format: "%.0f", value)
    }
}
