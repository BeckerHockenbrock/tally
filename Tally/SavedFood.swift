import Foundation
import SwiftData

@Model
final class SavedFood {
    var barcode: String
    var name: String
    var payload: Data
    var fetchedAt: Date
    var lastUsedAt: Date

    init(food: Food) throws {
        barcode = food.barcode
        name = food.name
        payload = try JSONEncoder().encode(food)
        fetchedAt = Date()
        lastUsedAt = Date()
    }

    var food: Food? { try? JSONDecoder().decode(Food.self, from: payload) }
}

struct FoodLookup {
    let food: Food
    let warning: String?
}

/// Cache writes use their own context and never block logging usable nutrition.
@MainActor
struct FoodStore {
    static let cacheLifetime: TimeInterval = 7 * 24 * 60 * 60
    let container: ModelContainer
    var fetchFood: (String) async throws -> Food = { try await FoodAPIService.shared.lookup(barcode: $0) }
    var saveCache: (ModelContext) throws -> Void = { try $0.save() }

    func lookup(_ input: String, refresh: Bool = false) async throws -> FoodLookup {
        let code = FoodBarcode.cacheKey(try FoodBarcode.validated(input))
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<SavedFood>(predicate: #Predicate { $0.barcode == code })
        let existing = try context.fetch(descriptor).first
        let cachedFood = existing?.food
        if !refresh, let existing, let food = cachedFood,
           Date().timeIntervalSince(existing.fetchedAt) < Self.cacheLifetime {
            existing.lastUsedAt = Date()
            // This timestamp is only used to order the recent-food list.
            try? saveCache(context)
            return FoodLookup(food: food, warning: nil)
        }

        let food: Food
        do {
            food = try await fetchFood(code)
            try Task.checkCancellation()
        } catch {
            try Task.checkCancellation()
            // Explicit refresh must report failures, not imply a successful update.
            guard !refresh, let cachedFood, let existing, canUseOfflineCache(after: error) else { throw error }
            return FoodLookup(food: cachedFood,
                warning: "Using nutrition saved on \(existing.fetchedAt.formatted(date: .abbreviated, time: .omitted)). Refresh failed. Check the package before logging.")
        }

        do {
            if let existing {
                existing.payload = try JSONEncoder().encode(food)
                existing.name = food.name
                existing.fetchedAt = Date()
                existing.lastUsedAt = Date()
            } else {
                context.insert(try SavedFood(food: food))
            }
            try saveCache(context)
            return FoodLookup(food: food, warning: nil)
        } catch {
            context.rollback()
            return FoodLookup(food: food, warning: "Food loaded, but could not be saved for offline reuse. Check available storage.")
        }
    }

    private func canUseOfflineCache(after error: Error) -> Bool {
        if let error = error as? URLError { return error.code != .cancelled }
        guard let error = error as? FoodAPIError else { return false }
        switch error {
        case .network, .timeout, .rateLimited: return true
        case .server(let status): return status >= 500
        default: return false
        }
    }
}
