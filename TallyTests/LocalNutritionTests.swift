import Foundation
import SwiftData
import Testing
@testable import Tally

struct LocalNutritionTests {
    private func food(_ code: String = "0012345678905", custom: Bool = false) -> Food {
        Food(barcode: code, name: "Test food", brand: nil, imageURL: nil, servingSize: nil,
             portions: [FoodPortion(unit: .grams, nutrition: FoodNutrition(calories: 1, protein: 0.1, carbs: 0.1, fat: 0.01,
                 nutrients: ["iron": NutrientAmount(name: "Iron", unit: "mg", amount: 0.02, source: "Test")]))],
             source: custom ? "Manual" : nil)
    }

    @Test func bundledLibraryHasStaplesAndFullNutrients() throws {
        #expect(LocalFoodLibrary.errorMessage == nil)
        #expect((40...60).contains(LocalFoodLibrary.foods.count))
        for query in ["white rice", "brown rice", "pasta", "chicken breast", "banana", "broccoli"] {
            #expect(!LocalFoodLibrary.search(query).isEmpty)
        }
        for food in LocalFoodLibrary.foods {
            #expect(food.isBuiltIn)
            let nutrition = try #require(food.portions.first?.nutrition)
            #expect(nutrition.isComplete)
            #expect((nutrition.nutrients?.count ?? 0) > 10)
            #expect(nutrition.scaled(by: 100) != nil)
        }
        #expect(LocalFoodLibrary.search("rice").map(\.name) == ["White Rice", "Brown Rice"])
        #expect(LocalFoodLibrary.search("pasta").map(\.name) == ["Pasta"])
        #expect(Set(LocalFoodLibrary.foods.map(\.name)).count == LocalFoodLibrary.foods.count)
        #expect(LocalFoodLibrary.foods.allSatisfy { $0.icon?.isEmpty == false && $0.preparation?.isEmpty == false })
        let chicken = try #require(LocalFoodLibrary.search("chicken breast").first)
        #expect(chicken.preparation == "Cooked, skinless")
        #expect(chicken.portions.first?.nutrition.nutrients?["selenium"]?.unit == "µg")
        #expect(chicken.portions.first?.nutrition.nutrients?["vitamin-b12"] != nil)
    }

    @Test func localSearchMatchesAllWordsAndIncludesSavedFoods() {
        let saved = food(custom: true)
        #expect(LocalFoodLibrary.search("test FOOD", saved: [saved]).map(\.id) == [saved.id])
        #expect(LocalFoodLibrary.search("notarealfood123").isEmpty)
        #expect(LocalFoodLibrary.search("test", saved: [saved, saved]).count == 1)
    }

    @Test func scalingPreservesUnitsSourceAndUnknowns() throws {
        let nutrition = try #require(food().portions.first?.nutrition.scaled(by: 150))
        #expect(nutrition.nutrients?["iron"]?.amount == 3)
        #expect(nutrition.nutrients?["iron"]?.unit == "mg")
        #expect(nutrition.nutrients?["iron"]?.source == "Test")
        #expect(nutrition.nutrients?["vitamin-c"] == nil)
        var bad = food().portions[0].nutrition
        bad.nutrients?["iron"]?.amount = .greatestFiniteMagnitude
        #expect(bad.scaled(by: 150) == nil)
    }

    @Test func legacyFoodPayloadStillDecodes() throws {
        let data = Data(#"{"barcode":"0012345678905","name":"Old food","portions":[{"unit":"grams","nutrition":{"calories":1,"protein":0,"carbs":0,"fat":0,"energyEstimated":false}}]}"#.utf8)
        let legacy = try JSONDecoder().decode(Food.self, from: data)
        #expect(legacy.sourceName == "Open Food Facts")
        #expect(legacy.cartoonIcon == "🍽️")
        #expect(FoodEmoji.forName("Pineapple") == "🍍")
        #expect(FoodEmoji.forName("Peanut butter") == "🥜")
        #expect(legacy.portions.first?.nutrition.nutrients == nil)
        #expect(legacy.portions.first?.nutrition.isComplete == true)
    }

    @Test func barcodeNutrientsNormalizeMassAndKeepVitaminFormsSeparate() throws {
        let data = Data(#"{"status":"success","product":{"nutrition":{"aggregated_set":{"preparation":"as_sold","per":"100g","nutrients":{"proteins":{"value":10,"unit":"g"},"carbohydrates":{"value":20,"unit":"g"},"fat":{"value":3,"unit":"g"},"iron":{"value":0.004,"unit":"g"},"vitamin-b12":{"value":0.003,"unit":"mg"},"vitamin-a":{"value":250,"unit":"IU"},"calcium":{"value":100,"unit":"mg","modifier":"<"},"fiber":{"value":0,"unit":"g"}}}}}}"#.utf8)
        let result = try FoodAPIService.decode(data, requestedBarcode: "0012345678905")
        let portion = try #require(result.portions.first?.nutrition.scaled(by: 150))
        #expect(abs(try #require(portion.nutrients?["iron"]?.amount) - 6) < 1e-9)
        #expect(abs(try #require(portion.nutrients?["vitamin-b12"]?.amount) - 4.5) < 1e-9)
        #expect(portion.nutrients?["vitamin-a-iu"]?.amount == 375)
        #expect(portion.nutrients?["vitamin-a-rae"] == nil)
        #expect(portion.nutrients?["calcium"] == nil)
        #expect(portion.nutrients?["fiber"]?.amount == 0)
    }

    @Test @MainActor func totalsDistinguishUnknownZeroAndPartial() throws {
        let first = MacroEntry(protein: 1)
        try first.setNutrition(FoodNutrition(calories: 100, protein: 1, carbs: 1, fat: 1,
            nutrients: ["iron": NutrientAmount(name: "Iron", unit: "mg", amount: 2),
                        "fiber": NutrientAmount(name: "Fiber", unit: "g", amount: 0)]))
        let second = MacroEntry(protein: 1) // Legacy/manual entry has no micros.
        let totals = NutritionTotals.calculate(entries: [first, second])
        let iron = try #require(totals.first { $0.id == "iron" })
        #expect(iron.amount == 2)
        #expect(iron.knownEntries == 1)
        #expect(!iron.isComplete)
        #expect(totals.first { $0.id == "fiber" }?.amount == 0)
        #expect(totals.first { $0.id == "vitamin-c" }?.amount == nil)
        #expect(NutritionTotals.calculate(entries: [first]).first { $0.id == "iron" }?.isComplete == true)
    }

    @Test @MainActor func expirationUsesThreeCalendarMonthsAndNeverExpiresCustomFoods() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let scanned = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 31, hour: 12)))
        let expiry = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 30, hour: 12)))
        let saved = try SavedFood(food: food(), now: scanned)
        #expect(!saved.isExpired(at: expiry.addingTimeInterval(-1), calendar: calendar))
        #expect(saved.isExpired(at: expiry, calendar: calendar))
        let custom = try SavedFood(food: food("custom:test", custom: true), now: scanned)
        #expect(!custom.isExpired(at: expiry.addingTimeInterval(100_000_000), calendar: calendar))
    }

    @Test @MainActor func browsingDoesNotRenewRetentionButLoggingDoes() async throws {
        let container = try ModelContainer(for: SavedFood.self, MacroEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let scanned = Date().addingTimeInterval(-30 * 86_400)
        let saved = try SavedFood(food: food(), now: scanned)
        context.insert(saved)
        try context.save()
        let store = FoodStore(container: container, fetchFood: { _ in Issue.record("Unexpected network request"); throw URLError(.notConnectedToInternet) })
        _ = try await store.lookup("012345678905")
        #expect(try ModelContext(container).fetch(FetchDescriptor<SavedFood>()).first?.lastUsedAt == scanned)
        let loggedAt = Date()
        try FoodStore.recordUse(of: food(), in: context, now: loggedAt)
        try context.save()
        #expect(try ModelContext(container).fetch(FetchDescriptor<SavedFood>()).first?.lastUsedAt == loggedAt)
    }

    @Test @MainActor func cleanupDeletesOnlyExpiredProductsAndPreservesDiarySnapshots() throws {
        let container = try ModelContainer(for: SavedFood.self, MacroEntry.self, MacroGoal.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let old = Calendar.current.date(byAdding: .month, value: -4, to: Date())!
        context.insert(try SavedFood(food: food(), now: old))
        context.insert(try SavedFood(food: food("custom:test", custom: true), now: old))
        context.insert(try SavedFood(food: food("12345678")))
        let entry = MacroEntry(name: "Historical food")
        try entry.setNutrition(try #require(food().portions.first?.nutrition.scaled(by: 150)))
        context.insert(entry)
        context.insert(MacroGoal())
        try context.save()
        try FoodStore(container: container).removeExpired()
        let reread = ModelContext(container)
        #expect(try reread.fetch(FetchDescriptor<SavedFood>()).count == 2)
        let snapshot = try #require(reread.fetch(FetchDescriptor<MacroEntry>()).first)
        #expect(snapshot.nutrition.nutrients?["iron"]?.amount == 3)
        #expect(snapshot.calories == 150)
        #expect(try reread.fetch(FetchDescriptor<MacroGoal>()).count == 1)
    }

    @Test @MainActor func failedLoggingCanRollBackRetentionAndCustomFoodWrites() throws {
        let container = try ModelContainer(for: SavedFood.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let old = Date().addingTimeInterval(-86_400)
        context.insert(try SavedFood(food: food(), now: old))
        try context.save()
        try FoodStore.recordUse(of: food(), in: context)
        try FoodStore.saveCustom(food("custom:test", custom: true), in: context)
        context.rollback()
        let saved = try context.fetch(FetchDescriptor<SavedFood>())
        #expect(saved.count == 1)
        #expect(saved.first?.lastUsedAt == old)
    }
}

/// The previous on-disk entity, before nutritionPayload was added.
private enum BeforeNutrientSnapshots {
    @Model final class MacroEntry {
        var id: UUID
        var name: String
        var protein: Double
        var carbs: Double
        var fat: Double
        var date: Date
        var reportedCalories: Double?
        var barcode: String?
        var portionDescription: String?
        var dataSource: String?
        var energyIsEstimated: Bool?

        init() {
            id = UUID()
            name = "Before nutrient tracking"
            protein = 30
            carbs = 40
            fat = 5
            date = Date(timeIntervalSince1970: 1_700_000_000)
            reportedCalories = 330
        }
    }
}

extension LocalNutritionTests {
    @Test @MainActor func existingDiskStoreMigratesWithoutLosingDiaryGoalsOrFoods() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("default.store")
        try autoreleasepool {
            let schema = Schema([BeforeNutrientSnapshots.MacroEntry.self, MacroGoal.self, SavedFood.self])
            let container = try ModelContainer(for: schema,
                configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
            let context = ModelContext(container)
            context.insert(BeforeNutrientSnapshots.MacroEntry())
            context.insert(MacroGoal(protein: 150))
            let saved = try SavedFood(food: food())
            // Exact pre-change JSON: no Food.source and no FoodNutrition.nutrients.
            saved.payload = Data(#"{"barcode":"0012345678905","name":"Old saved food","portions":[{"unit":"grams","nutrition":{"calories":1,"protein":0,"carbs":0,"fat":0,"energyEstimated":false}}]}"#.utf8)
            context.insert(saved)
            try context.save()
        }
        let schema = Schema([MacroEntry.self, MacroGoal.self, SavedFood.self])
        let container = try ModelContainer(for: schema,
            configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
        let context = ModelContext(container)
        let entry = try #require(context.fetch(FetchDescriptor<MacroEntry>()).first)
        #expect(entry.name == "Before nutrient tracking")
        #expect(entry.protein == 30)
        #expect(entry.calories == 330)
        #expect(entry.nutrition.nutrients == nil)
        #expect(try context.fetch(FetchDescriptor<MacroGoal>()).first?.protein == 150)
        #expect(try context.fetch(FetchDescriptor<SavedFood>()).first?.food?.name == "Old saved food")
        try entry.setNutrition(FoodNutrition(calories: 330, protein: 30, carbs: 40, fat: 5,
            nutrients: ["iron": NutrientAmount(name: "Iron", unit: "mg", amount: 2)]))
        try context.save()
        #expect(try ModelContext(container).fetch(FetchDescriptor<MacroEntry>()).first?.nutrition.nutrients?["iron"]?.amount == 2)
    }
}
