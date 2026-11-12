import Foundation

enum FoodAPIError: LocalizedError {
    case invalidBarcode, notFound, malformedResponse, configuration
    case rateLimited(Date), server(Int), network(String), timeout

    var errorDescription: String? {
        switch self {
        case .invalidBarcode: "Enter an 8, 12, or 13 digit product barcode."
        case .notFound: "This barcode is not in Open Food Facts. You can enter the label's nutrition manually."
        case .malformedResponse: "Open Food Facts returned a response Tally could not read."
        case .configuration: "Set FoodAPIConfiguration.contact to your real contact email before using food lookup."
        case .rateLimited(let date): "Too many lookups. Try again after \(date.formatted(date: .omitted, time: .standard))."
        case .server(let status): "Open Food Facts is unavailable (HTTP \(status)). Please try again later."
        case .network(let message): "Could not connect to Open Food Facts. \(message)"
        case .timeout: "Food lookup timed out. Check your connection and try again."
        }
    }
}

enum FoodAPIConfiguration {
    // Developer contact included in the Open Food Facts User-Agent.
    static let contact = "bhocken91@gmail.com"
    static let baseURL = "https://world.openfoodfacts.org"
}

/// Serializes requests and enforces a conservative 15 requests/minute per app process.
actor FoodAPIService {
    static let shared = FoodAPIService()
    private let session: URLSession
    private let contact: String
    private let baseURL: String
    private var requestDates: [Date] = []
    private var retryAfter: Date?

    init(session: URLSession = .shared, contact: String = FoodAPIConfiguration.contact,
         baseURL: String = FoodAPIConfiguration.baseURL) {
        self.session = session
        self.contact = contact
        self.baseURL = baseURL
    }

    func lookup(barcode: String) async throws -> Food {
        let code = try FoodBarcode.validated(barcode)
        guard !contact.contains("REPLACE_"), contact.contains("@"),
              !contact.contains("\n"), !contact.contains("\r") else { throw FoodAPIError.configuration }
        let now = Date()
        if let retryAfter, retryAfter > now { throw FoodAPIError.rateLimited(retryAfter) }
        requestDates.removeAll { now.timeIntervalSince($0) >= 60 }
        if requestDates.count >= 15, let first = requestDates.first {
            throw FoodAPIError.rateLimited(first.addingTimeInterval(60))
        }
        requestDates.append(now)
        guard let baseURL = URL(string: baseURL), baseURL.scheme == "https" else { throw FoodAPIError.configuration }
        var components = URLComponents(url: baseURL.appendingPathComponent("api/v3.6/product/\(code).json"),
                                       resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "fields", value:
            "code,product_name,product_name_en,brands,image_front_url,serving_size,serving_quantity,serving_quantity_unit,nutrition")]
        guard let url = components?.url else { throw FoodAPIError.invalidBarcode }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("Tally/1.0 (\(contact))", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if baseURL.host == "world.openfoodfacts.net" {
            request.setValue("Basic " + Data("off:off".utf8).base64EncodedString(), forHTTPHeaderField: "Authorization")
        }
        do {
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse else { throw FoodAPIError.malformedResponse }
            switch http.statusCode {
            case 200: return try Self.decode(data, requestedBarcode: code)
            case 404: throw FoodAPIError.notFound
            case 429:
                let header = http.value(forHTTPHeaderField: "Retry-After") ?? ""
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = TimeZone(secondsFromGMT: 0)
                formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
                let date = Double(header).flatMap { $0.isFinite ? Date().addingTimeInterval(min(86_400, max(1, $0))) : nil }
                    ?? formatter.date(from: header) ?? Date().addingTimeInterval(60)
                retryAfter = date
                throw FoodAPIError.rateLimited(date)
            default: throw FoodAPIError.server(http.statusCode)
            }
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            if error.code == .timedOut { throw FoodAPIError.timeout }
            throw FoodAPIError.network(error.localizedDescription)
        }
    }

    static func decode(_ data: Data, requestedBarcode: String) throws -> Food {
        let envelope: OFFResponse
        do { envelope = try JSONDecoder().decode(OFFResponse.self, from: data) }
        catch { throw FoodAPIError.malformedResponse }
        if envelope.result?.id == "product_not_found" { throw FoodAPIError.notFound }
        guard envelope.status == "success" || envelope.status == "success_with_warnings",
              let product = envelope.product else { throw FoodAPIError.malformedResponse }
        return product.food(barcode: requestedBarcode)
    }
}

private struct OFFResponse: Decodable {
    let status: String?
    let result: Result?
    let product: OFFProduct?
    struct Result: Decodable { let id: String? }
}

/// OFF occasionally serializes numeric fields as strings.
private struct FlexibleNumber: Decodable {
    let value: Double?
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let number = (try? container.decode(Double.self))
            ?? (try? container.decode(String.self)).flatMap(Double.init)
        value = number.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
    }
}

private struct OFFProduct: Decodable {
    let code: String?
    let product_name: String?
    let product_name_en: String?
    let brands: String?
    let image_front_url: String?
    let serving_size: String?
    let serving_quantity: FlexibleNumber?
    let serving_quantity_unit: String?
    let nutrition: OFFNutrition?

    func food(barcode: String) -> Food {
        var portions: [FoodPortion] = []
        // Never combine prepared and as-sold nutrition, or invent a liquid's density.
        let sets = (nutrition?.input_sets ?? []).filter { $0.preparation == "as_sold" }
        let aggregate = nutrition?.aggregated_set
        let weight = aggregate.flatMap { $0.preparation == "as_sold" && $0.per == "100g" ? $0 : nil }
            ?? sets.first { $0.per == "100g" }
        let volume = aggregate.flatMap { $0.preparation == "as_sold" && $0.per == "100ml" ? $0 : nil }
            ?? sets.first { $0.per == "100ml" }
        if let n = weight?.values.scaled(by: 0.01) { portions.append(FoodPortion(unit: .grams, nutrition: n)) }
        if let n = volume?.values.scaled(by: 0.01) { portions.append(FoodPortion(unit: .milliliters, nutrition: n)) }

        if let serving = sets.first(where: { $0.per == "serving" && $0.values.isComplete }) {
            portions.append(FoodPortion(unit: .servings, nutrition: serving.values))
            if let quantity = serving.per_quantity?.value, quantity > 0 {
                let unit = serving.per_unit?.lowercased()
                if unit == "g", weight == nil, let n = serving.values.scaled(by: 1 / quantity) {
                    portions.append(FoodPortion(unit: .grams, nutrition: n))
                } else if unit == "ml", volume == nil, let n = serving.values.scaled(by: 1 / quantity) {
                    portions.append(FoodPortion(unit: .milliliters, nutrition: n))
                }
            }
        } else if let quantity = serving_quantity?.value, quantity > 0,
                  let unit = serving_quantity_unit?.lowercased(),
                  let base = portions.first(where: { (unit == "g" && $0.unit == .grams) || (unit == "ml" && $0.unit == .milliliters) }),
                  let n = base.nutrition.scaled(by: quantity) {
            portions.append(FoodPortion(unit: .servings, nutrition: n))
        } else if let serving = sets.first(where: { $0.per == "serving" }) {
            portions.append(FoodPortion(unit: .servings, nutrition: serving.values))
        }
        let name = [product_name, product_name_en].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? "Unnamed food"
        let image = image_front_url.flatMap(URL.init(string:)).flatMap { $0.scheme == "https" ? $0 : nil }
        return Food(barcode: FoodBarcode.cacheKey(barcode), name: name, brand: brands, imageURL: image,
                    servingSize: serving_size, portions: portions)
    }
}

private struct OFFNutrition: Decodable {
    let aggregated_set: OFFNutrientSet?
    let input_sets: [OFFNutrientSet]?
}

private struct OFFNutrientSet: Decodable {
    let per: String?
    let preparation: String?
    let per_quantity: FlexibleNumber?
    let per_unit: String?
    let source: String?
    let nutrients: [String: OFFNutrient]?

    var values: FoodNutrition {
        let p = nutrients?["proteins"]?.grams
        let c = nutrients?["carbohydrates-total"]?.grams ?? nutrients?["carbohydrates"]?.grams
        let f = nutrients?["fat"]?.grams
        let energyNutrient = ["energy-kcal", "energy-kj", "energy"]
            .compactMap { nutrients?[$0] }
            .first { $0.kilocalories != nil }
        let energy = energyNutrient?.kilocalories
        let estimate: Double? = if let p, let c, let f { p * 4 + c * 4 + f * 9 } else { nil }
        return FoodNutrition(calories: energy ?? estimate, protein: p, carbs: c, fat: f,
                             energyEstimated: energy == nil || energyNutrient?.source == "estimate" || source == "estimate")
    }
}

private struct OFFNutrient: Decodable {
    let value: FlexibleNumber?
    let unit: String?
    let modifier: String?
    let source: String?

    // "<" and ">" are bounds, not exact quantities. Ask for manual confirmation instead.
    var amount: Double? {
        guard modifier == nil || modifier == "" || modifier == "=" || modifier == "~" else { return nil }
        return value?.value
    }

    var grams: Double? {
        guard let amount else { return nil }
        switch unit?.lowercased() {
        case "g": return amount
        case "mg": return amount / 1000
        case "µg", "μg", "ug": return amount / 1_000_000
        case "kg": return amount * 1000
        default: return nil
        }
    }

    var kilocalories: Double? {
        guard let amount else { return nil }
        switch unit?.lowercased() {
        case "kcal": return amount
        case "kj": return amount / 4.184
        default: return nil
        }
    }
}
