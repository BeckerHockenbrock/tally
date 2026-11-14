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
    var nutritionPayload: Data?
    
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
    
    /// A diary owns its values, independent of the reusable food and its expiry.
    var nutrition: FoodNutrition {
        if let nutritionPayload, let snapshot = try? JSONDecoder().decode(FoodNutrition.self, from: nutritionPayload) {
            return snapshot
        }
        return FoodNutrition(calories: calories, protein: protein, carbs: carbs, fat: fat,
                             energyEstimated: energyIsEstimated ?? (reportedCalories == nil))
    }

    func setNutrition(_ nutrition: FoodNutrition) throws {
        nutritionPayload = try JSONEncoder().encode(nutrition)
        protein = nutrition.protein ?? 0
        carbs = nutrition.carbs ?? 0
        fat = nutrition.fat ?? 0
        reportedCalories = nutrition.calories
        energyIsEstimated = nutrition.energyEstimated
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


/// A value copy survives SwiftData deletion and restores the exact diary record.
struct EntrySnapshot {
    let id: UUID
    let name: String
    let protein: Double
    let carbs: Double
    let fat: Double
    let date: Date
    let reportedCalories: Double?
    let barcode: String?
    let portionDescription: String?
    let dataSource: String?
    let energyIsEstimated: Bool?
    let nutritionPayload: Data?

    init(_ entry: MacroEntry) {
        id = entry.id; name = entry.name; protein = entry.protein
        carbs = entry.carbs; fat = entry.fat; date = entry.date
        reportedCalories = entry.reportedCalories; barcode = entry.barcode
        portionDescription = entry.portionDescription; dataSource = entry.dataSource
        energyIsEstimated = entry.energyIsEstimated; nutritionPayload = entry.nutritionPayload
    }

    func restore() -> MacroEntry {
        let entry = MacroEntry(id: id, name: name, protein: protein, carbs: carbs, fat: fat, date: date)
        entry.reportedCalories = reportedCalories; entry.barcode = barcode
        entry.portionDescription = portionDescription; entry.dataSource = dataSource
        entry.energyIsEstimated = energyIsEstimated; entry.nutritionPayload = nutritionPayload
        return entry
    }
}

enum DiaryPeriod: String, CaseIterable, Identifiable {
    case overnight = "Overnight", morning = "Morning", afternoon = "Afternoon", evening = "Evening"
    var id: String { rawValue }

    static func period(for date: Date, calendar: Calendar = .current) -> Self {
        switch calendar.component(.hour, from: date) {
        case 0..<6: .overnight
        case 6..<12: .morning
        case 12..<18: .afternoon
        default: .evening
        }
    }
}

extension DiaryDates {
    static func week(containing date: Date, calendar: Calendar = .current) -> [Date] {
        guard let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }
}
