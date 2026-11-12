import Foundation
import SwiftData
import Testing
@testable import Tally

struct RegressionTests {
    @Test func progressHandlesExtremeAndInvalidNumbers() {
        #expect(MacroProgress.percentLabel(consumed: 1, goal: 1e-18) == "999999+%")
        #expect(MacroProgress.percentLabel(consumed: .greatestFiniteMagnitude, goal: .leastNonzeroMagnitude) == "999999+%")
        #expect(MacroProgress.percentLabel(consumed: 12.5, goal: 100) == "12%")
        for invalid in [Double.nan, .infinity, -.infinity, -1] {
            #expect(MacroProgress.fraction(consumed: invalid, goal: 100) == 0)
            #expect(MacroProgress.fraction(consumed: 100, goal: invalid) == 0)
        }
        #expect(MacroProgress.fraction(consumed: 1, goal: 1e-18) == 1)
        #expect(MacroProgress.percentLabel(consumed: 0, goal: 0) == "0%")
    }

    @Test func goalsRejectInvalidInputAndPreservePrecision() {
        for input in ["", "abc", "nan", "inf", "1e309", "-1", "1e-18", "100001"] {
            #expect(GoalInput.value(input) == nil)
        }
        #expect(GoalInput.value("0") == 0)
        #expect(GoalInput.value(" 140,25 ") == 140.25)
        #expect(GoalInput.value("99", calories: true) == nil)
        #expect(GoalInput.value("2000", calories: true) == 2000)
        for value in [140.25, 65.123456789, 2000.75] {
            #expect(Double(GoalInput.editingText(value)) == value)
        }
    }

    @Test func loggingUsesCurrentTimeAndPreservesHistoricalDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let selected = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: 8)))
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 19, minute: 45)))
        #expect(DiaryDates.entryDate(selectedDate: selected, followsToday: true, now: now, calendar: calendar) == now)
        let historical = DiaryDates.entryDate(selectedDate: selected, followsToday: false, now: now, calendar: calendar)
        #expect(calendar.isDate(historical, inSameDayAs: selected))
        #expect(calendar.component(.hour, from: historical) == 19)
        #expect(calendar.component(.minute, from: historical) == 45)
    }

    @Test @MainActor func dayQueryHandlesDSTAndExcludesAdjacentDays() throws {
        let container = try ModelContainer(for: MacroEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        for (month, day, hours) in [(3, 8, 23), (11, 1, 25)] {
            let start = try #require(calendar.date(from: DateComponents(year: 2026, month: month, day: day)))
            let end = try #require(calendar.date(byAdding: .day, value: 1, to: start))
            #expect(end.timeIntervalSince(start) == Double(hours * 3600))
            for (offset, name) in [(-1.0, "before"), (0.0, "start"), (end.timeIntervalSince(start) - 1, "last"), (end.timeIntervalSince(start), "after")] {
                context.insert(MacroEntry(name: name, protein: 1, date: start.addingTimeInterval(offset)))
            }
            try context.save()
            let entries = try context.fetch(DiaryDates.descriptor(for: start, calendar: calendar))
            #expect(entries.map(\.name) == ["last", "start"])
            #expect(DiaryTotals(entries: entries).protein == 2)
        }
    }

    @MainActor private func cachedStore(expired: Bool) throws -> (ModelContainer, Food) {
        let container = try ModelContainer(for: SavedFood.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let food = Food(barcode: "0012345678905", name: "Saved", brand: nil,
                        imageURL: nil, servingSize: nil, portions: [])
        let context = ModelContext(container)
        let saved = try SavedFood(food: food)
        if expired { saved.fetchedAt = Date().addingTimeInterval(-FoodStore.cacheLifetime - 10) }
        context.insert(saved)
        try context.save()
        return (container, food)
    }

    @Test @MainActor func expiredCacheRefreshesAndPersistsNewDefinition() async throws {
        let (container, _) = try cachedStore(expired: true)
        let fresh = Food(barcode: "0012345678905", name: "Updated", brand: nil,
                         imageURL: nil, servingSize: nil, portions: [])
        var calls = 0
        let store = FoodStore(container: container, fetchFood: { _ in calls += 1; return fresh })
        let result = try await store.lookup("012345678905")
        #expect(calls == 1)
        #expect(result.food.name == "Updated")
        #expect(result.warning == nil)
        let context = ModelContext(container)
        #expect(try context.fetch(FetchDescriptor<SavedFood>()).first?.food?.name == "Updated")
    }

    @Test @MainActor func expiredCacheWorksOfflineWithWarningButRefreshReportsFailure() async throws {
        let (container, _) = try cachedStore(expired: true)
        let offline = FoodStore(container: container, fetchFood: { _ in throw URLError(.notConnectedToInternet) })
        let result = try await offline.lookup("012345678905")
        #expect(result.food.name == "Saved")
        #expect(result.warning != nil)
        await #expect(throws: URLError.self) { try await offline.lookup("012345678905", refresh: true) }
        let deleted = FoodStore(container: container, fetchFood: { _ in throw FoodAPIError.notFound })
        await #expect(throws: FoodAPIError.self) { try await deleted.lookup("012345678905") }
        let cancelled = FoodStore(container: container, fetchFood: { _ in throw CancellationError() })
        await #expect(throws: CancellationError.self) { try await cancelled.lookup("012345678905") }
    }

    @Test @MainActor func cacheWriteFailuresDoNotBlockUsableFood() async throws {
        let (container, food) = try cachedStore(expired: false)
        let store = FoodStore(container: container,
                              fetchFood: { _ in food },
                              saveCache: { _ in throw CocoaError(.fileWriteOutOfSpace) })
        let cached = try await store.lookup("012345678905")
        #expect(cached.food == food)
        let fetched = try await store.lookup("012345678905", refresh: true)
        #expect(fetched.food == food)
        #expect(fetched.warning != nil)
    }
}
