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
    // Optional additions allow existing stores to migrate without changing old entries.
    var reportedCalories: Double?
    var barcode: String?
    var portionDescription: String?
    var dataSource: String?
    var energyIsEstimated: Bool?
    
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
        reportedCalories ?? ((protein * 4.0) + (carbs * 4.0) + (fat * 9.0))
    }
    
    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Quick Entry" : trimmed
    }
}

/// Calendar boundaries correctly handle 23- and 25-hour days.
enum DiaryDates {
    static func descriptor(for date: Date, calendar: Calendar = .current) -> FetchDescriptor<MacroEntry> {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        return FetchDescriptor(predicate: #Predicate<MacroEntry> { $0.date >= start && $0.date < end },
                               sortBy: [SortDescriptor(\MacroEntry.date, order: .reverse)])
    }

    static func entryDate(selectedDate: Date, followsToday: Bool, now: Date = Date(),
                          calendar: Calendar = .current) -> Date {
        if followsToday { return now }
        let time = calendar.dateComponents([.hour, .minute, .second], from: now)
        return calendar.date(bySettingHour: time.hour ?? 12, minute: time.minute ?? 0,
                             second: time.second ?? 0, of: selectedDate) ?? selectedDate
    }
}

struct DiaryTotals {
    var calories = 0.0
    var protein = 0.0
    var carbs = 0.0
    var fat = 0.0

    init(entries: [MacroEntry]) {
        for entry in entries {
            calories += entry.calories
            protein += entry.protein
            carbs += entry.carbs
            fat += entry.fat
        }
    }
}
