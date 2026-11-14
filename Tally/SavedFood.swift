import Foundation
import SwiftData

@Model
final class SavedFood {
    var barcode: String
    var name: String
    var payload: Data
    var fetchedAt: Date
    /// First scan, then the most recent time actually added to the diary. Viewing never renews it.
    var lastUsedAt: Date

    init(food: Food, now: Date = Date()) throws {
        barcode = food.barcode
        name = food.name
        payload = try JSONEncoder().encode(food)
        fetchedAt = now
        lastUsedAt = now
    }

    var food: Food? { try? JSONDecoder().decode(Food.self, from: payload) }
    var isCustom: Bool { food?.isCustom == true }

    func isExpired(at now: Date, calendar: Calendar = .current) -> Bool {
        guard !isCustom else { return false }
        guard let expiry = calendar.date(byAdding: .month, value: 3, to: lastUsedAt) else { return false }
        return expiry <= now
    }
}

struct FoodLookup {
    let food: Food
    let warning: String?
}

@MainActor
struct FoodStore {
    let container: ModelContainer
    var fetchFood: (String) async throws -> Food = { try await FoodAPIService.shared.lookup(barcode: $0) }
    var saveCache: (ModelContext) throws -> Void = { try $0.save() }
    var now: () -> Date = { Date() }

    func removeExpired() throws {
        let context = ModelContext(container)
        for saved in try context.fetch(FetchDescriptor<SavedFood>()) where saved.isExpired(at: now()) {
            context.delete(saved)
        }
        if context.hasChanges { try saveCache(context) }
    }

    func lookup(_ input: String, refresh: Bool = false) async throws -> FoodLookup {
        let code = FoodBarcode.cacheKey(try FoodBarcode.validated(input))
        try removeExpired()
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<SavedFood>(predicate: #Predicate { $0.barcode == code })
        let existing = try context.fetch(descriptor).first
        if !refresh, let food = existing?.food {
            return FoodLookup(food: food, warning: nil)
        }
        let food = try await fetchFood(code)
        try Task.checkCancellation()
        do {
            if let existing {
                existing.payload = try JSONEncoder().encode(food)
                existing.name = food.name
                existing.fetchedAt = now()
                // A refresh does not count as eating this food.
            } else {
                context.insert(try SavedFood(food: food, now: now()))
            }
            try saveCache(context)
            return FoodLookup(food: food, warning: nil)
        } catch {
            context.rollback()
            return FoodLookup(food: food, warning: "Food loaded, but could not be saved for offline reuse. Check available storage.")
        }
    }

    /// Called in the diary's transaction so a failed log cannot extend retention.
    static func recordUse(of food: Food, in context: ModelContext, now: Date = Date()) throws {
        guard !food.isBuiltIn else { return }
        let code = food.barcode
        let existing = try context.fetch(FetchDescriptor<SavedFood>(predicate: #Predicate { $0.barcode == code })).first
        if let existing { existing.lastUsedAt = now }
        else { context.insert(try SavedFood(food: food, now: now)) }
    }

    static func saveCustom(_ food: Food, in context: ModelContext) throws {
        let code = food.barcode
        if let saved = try context.fetch(FetchDescriptor<SavedFood>(predicate: #Predicate { $0.barcode == code })).first {
            saved.payload = try JSONEncoder().encode(food)
            saved.name = food.name
            saved.lastUsedAt = Date()
        } else { context.insert(try SavedFood(food: food)) }
    }
}
