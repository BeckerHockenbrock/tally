import Foundation
import SwiftData
import Testing
@testable import Tally

struct PolishTests {
    @Test func periodsAndWeeksRespectLocalCalendar() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        calendar.firstWeekday = 1
        for (hour, minute, expected) in [(0, 0, DiaryPeriod.overnight), (5, 59, .overnight), (6, 0, .morning), (11, 59, .morning), (12, 0, .afternoon), (17, 59, .afternoon), (18, 0, .evening), (23, 59, .evening)] {
            let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 13, hour: hour, minute: minute)))
            #expect(DiaryPeriod.period(for: date, calendar: calendar) == expected)
        }
        for month in [3, 11] {
            let date = try #require(calendar.date(from: DateComponents(year: 2026, month: month, day: month == 3 ? 8 : 1)))
            let week = DiaryDates.week(containing: date, calendar: calendar)
            #expect(week.count == 7)
            #expect(Set(week).count == 7)
            for (offset, day) in week.enumerated() {
                #expect(calendar.dateComponents([.day], from: week[0], to: day).day == offset)
                #expect(calendar.component(.hour, from: day) == 0)
            }
            let next = try #require(calendar.date(byAdding: .day, value: 7, to: date))
            #expect(Set(week).isDisjoint(with: DiaryDates.week(containing: next, calendar: calendar)))
        }
    }

    @Test @MainActor func recentFoodsUseLogsAndSkipDuplicatesAndExpiredCache() throws {
        let now = Date()
        var entries: [MacroEntry] = []
        var saved: [SavedFood] = []
        for index in 0..<7 {
            let food = Food(barcode: "test:\(index)", name: "Food \(index)", brand: nil, imageURL: nil, servingSize: nil, portions: [])
            saved.append(try SavedFood(food: food, now: now))
            let entry = MacroEntry(date: now.addingTimeInterval(Double(-index)))
            entry.barcode = food.barcode
            entries.append(entry)
        }
        let duplicate = MacroEntry(date: now.addingTimeInterval(1))
        duplicate.barcode = "test:0"
        entries.append(duplicate)
        let unavailable = MacroEntry(date: now.addingTimeInterval(2))
        unavailable.barcode = "missing"
        entries.append(unavailable)
        saved[1].lastUsedAt = Calendar.current.date(byAdding: .month, value: -4, to: now)!
        #expect(LocalFoodLibrary.recent(entries: entries.reversed(), saved: saved, now: now).map(\.id) == ["test:0", "test:2", "test:3", "test:4", "test:5"])
        #expect(LocalFoodLibrary.recent(entries: [], saved: saved).isEmpty)
        let builtIn = try #require(LocalFoodLibrary.foods.first)
        let entry = MacroEntry(); entry.barcode = builtIn.id
        #expect(LocalFoodLibrary.recent(entries: [entry], saved: []).first?.id == builtIn.id)
    }

    @Test @MainActor func undoRestoresEveryPersistedFieldAndOnlyLatestDeletion() throws {
        let container = try ModelContainer(for: MacroEntry.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let feedback = TallyFeedback()
        let entry = MacroEntry(name: "Original", protein: 3, carbs: 4, fat: 5, date: Date(timeIntervalSince1970: 12345))
        entry.reportedCalories = 99
        entry.barcode = "custom:test"
        entry.portionDescription = "2 servings"
        entry.dataSource = "Manual"
        entry.energyIsEstimated = false
        entry.nutritionPayload = Data([1, 2, 3])
        let snapshot = EntrySnapshot(entry)
        context.insert(entry)
        try context.save()
        try feedback.delete(entry, in: context)
        #expect(try context.fetchCount(FetchDescriptor<MacroEntry>()) == 0)
        try feedback.undo(in: context)
        let restored = try #require(context.fetch(FetchDescriptor<MacroEntry>()).first)
        #expect(restored.id == snapshot.id)
        #expect(restored.name == snapshot.name)
        #expect(restored.date == snapshot.date)
        #expect(restored.protein == snapshot.protein && restored.carbs == snapshot.carbs && restored.fat == snapshot.fat)
        #expect(restored.reportedCalories == snapshot.reportedCalories)
        #expect(restored.barcode == snapshot.barcode)
        #expect(restored.portionDescription == snapshot.portionDescription)
        #expect(restored.dataSource == snapshot.dataSource)
        #expect(restored.energyIsEstimated == snapshot.energyIsEstimated)
        #expect(restored.nutritionPayload == snapshot.nutritionPayload)
        try feedback.undo(in: context)
        #expect(try context.fetchCount(FetchDescriptor<MacroEntry>()) == 1)
        let second = MacroEntry(name: "Second")
        context.insert(second); try context.save()
        try feedback.delete(restored, in: context)
        try feedback.delete(second, in: context)
        try feedback.undo(in: context)
        #expect(try context.fetch(FetchDescriptor<MacroEntry>()).map(\.name) == ["Second"])
    }
}
