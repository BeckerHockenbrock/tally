import Foundation

enum LocalFoodLibrary {
    static let result: Result<[Food], Error> = Result {
        guard let url = Bundle.main.url(forResource: "CommonFoods", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode([Food].self, from: Data(contentsOf: url))
    }

    static var foods: [Food] { (try? result.get()) ?? [] }
    static var errorMessage: String? {
        if case .failure = result { return "The built-in food library could not load. Please reinstall or rebuild Tally. Your diary is still saved." }
        return nil
    }

    static func search(_ query: String, saved: [Food] = []) -> [Food] {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        let matches = (saved + foods).filter { food in
            let text = food.name + " " + (food.brand ?? "") + " " + (food.preparation ?? "")
            return words.allSatisfy { text.localizedStandardContains($0) }
        }
        var seen = Set<String>()
        return matches.filter { seen.insert($0.id).inserted }
    }
}


extension LocalFoodLibrary {
    static func recent(entries: [MacroEntry], saved: [SavedFood], now: Date = Date()) -> [Food] {
        let available = saved.filter { !$0.isExpired(at: now) }.compactMap(\.food) + foods
        var seen = Set<String>()
        var recent: [Food] = []
        for entry in entries.sorted(by: { $0.date > $1.date }) {
            guard let code = entry.barcode, !seen.contains(code),
                  let food = available.first(where: { $0.id == code }) else { continue }
            seen.insert(code)
            recent.append(food)
            if recent.count == 5 { break }
        }
        return recent
    }
}
