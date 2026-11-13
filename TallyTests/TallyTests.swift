import Foundation
import SwiftData
import Testing
@testable import Tally

@Suite(.serialized)
struct FoodTests {
    static let fixture = """
    {"status":"success","product":{"product_name":"Example food","brands":"Example",
    "serving_size":"one bar (50 g)","serving_quantity":50,"serving_quantity_unit":"g",
    "nutrition":{"aggregated_set":{"per":"100g","preparation":"as_sold","nutrients":{
    "proteins":{"value":"20","unit":"g"},"carbohydrates":{"value":30,"unit":"g"},
    "fat":{"value":10,"unit":"g"},"energy-kcal":{"value":305,"unit":"kcal"}}}}}}
    """

    func decode(_ json: String = fixture) throws -> Food {
        try FoodAPIService.decode(Data(json.utf8), requestedBarcode: "012345678905")
    }

    @Test func reportedEnergyAndPortions() throws {
        let food = try decode()
        let grams = try #require(food.portions.first { $0.unit == .grams })
        let consumed = try #require(grams.nutrition.scaled(by: 150))
        #expect(consumed.protein == 30)
        #expect(abs(try #require(consumed.calories) - 457.5) < 0.000001)
        #expect(consumed.energyEstimated == false)
        let serving = try #require(food.portions.first { $0.unit == .servings })
        #expect(serving.nutrition.protein == 10)
        #expect(serving.nutrition.scaled(by: 2)?.calories == 305)
    }

    @Test func missingIsNotZeroAndUnknownUnits() throws {
        let missing = Self.fixture.replacingOccurrences(of: #""fat":{"value":10,"unit":"g"},"#, with: "")
        let food = try decode(missing)
        #expect(food.portions.first?.nutrition.fat == nil)
        #expect(food.portions.first?.nutrition.isComplete == false)
        let unknown = try decode(Self.fixture.replacingOccurrences(of: #""unit":"g""#, with: #""unit":"scoops""#))
        #expect(unknown.portions.first?.nutrition.protein == nil)
    }

    @Test func energyConversionAndEstimate() throws {
        let kj = Self.fixture.replacingOccurrences(of: #""energy-kcal":{"value":305,"unit":"kcal"}"#,
                                                   with: #""energy-kj":{"value":1276.12,"unit":"kJ"}"#)
        let food = try decode(kj)
        #expect(abs((food.portions.first?.nutrition.calories ?? 0) - 3.05) < 0.00001)
        let absent = Self.fixture.replacingOccurrences(of: #","energy-kcal":{"value":305,"unit":"kcal"}"#, with: "")
        let estimate = try decode(absent)
        #expect(estimate.portions.first?.nutrition.energyEstimated == true)
        #expect(estimate.portions.first?.nutrition.calories == 2.9)
    }

    @Test func servingWithoutWeightAndLiquids() throws {
        let serving = """
        {"status":"success","product":{"nutrition":{"input_sets":[{"preparation":"as_sold",
        "per":"serving","nutrients":{"proteins":{"value":2,"unit":"g"},
        "carbohydrates":{"value":5,"unit":"g"},"fat":{"value":0,"unit":"g"}}}]}}}
        """
        let food = try decode(serving)
        #expect(food.portions.map(\.unit) == [.servings])
        #expect(food.portions.first?.nutrition.isComplete == true)
        let liquid = try decode(Self.fixture.replacingOccurrences(of: "100g", with: "100ml")
            .replacingOccurrences(of: #""serving_quantity_unit":"g""#, with: #""serving_quantity_unit":"ml""#))
        #expect(!liquid.portions.contains { $0.unit == .grams })
        #expect(liquid.portions.contains { $0.unit == .milliliters })
    }

    @Test func invalidQuantitiesAndPreparedData() throws {
        let nutrition = try #require(decode().portions.first?.nutrition)
        for quantity in [0, -1, Double.infinity, Double.nan, Double.greatestFiniteMagnitude] {
            if quantity == Double.greatestFiniteMagnitude {
                #expect(FoodNutrition(calories: 10, protein: 10, carbs: 10, fat: 10).scaled(by: quantity) == nil)
            } else { #expect(nutrition.scaled(by: quantity) == nil) }
        }
        #expect(try decode(Self.fixture.replacingOccurrences(of: "as_sold", with: "prepared")).portions.isEmpty)
    }

    @Test func malformedAndNotFound() {
        #expect(throws: FoodAPIError.self) { try decode("{}") }
        #expect(throws: FoodAPIError.self) { try decode("not JSON") }
        #expect(throws: FoodAPIError.self) {
            try decode(#"{"status":"failure","result":{"id":"product_not_found"}}"#)
        }
    }

    @Test func barcodeIdentityAndScanGate() throws {
        #expect(FoodBarcode.cacheKey("012345678905") == "0012345678905")
        #expect(FoodBarcode.cacheKey("0012345678905") == "0012345678905")
        #expect(FoodBarcode.cacheKey("00123456") == "00123456")
        #expect(FoodBarcode.expandUPCE("04252614") == "042100005264")
        #expect(throws: FoodAPIError.self) { try FoodBarcode.validated("123abc78") }
        var gate = BarcodeScanGate()
        let invalid = gate.accept("invalid")
        let first = gate.accept("012345678905")
        let repeated = gate.accept("012345678905")
        let other = gate.accept("12345678")
        #expect(!invalid)
        #expect(first)
        #expect(!repeated)
        #expect(!other)
    }

    @Test @MainActor func cacheAndDiaryPersistence() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: MacroEntry.self, MacroGoal.self, SavedFood.self, configurations: config)
        var count = 0
        let food = try decode()
        let store = FoodStore(container: container, fetchFood: { _ in count += 1; return food })
        _ = try await store.lookup("012345678905")
        _ = try await store.lookup("0012345678905")
        #expect(count == 1)
        _ = try await store.lookup("0012345678905", refresh: true)
        #expect(count == 2)
        let context = ModelContext(container)
        #expect(try context.fetch(FetchDescriptor<SavedFood>()).count == 1)
        let oldDate = Date(timeIntervalSince1970: 1000)
        let entry = MacroEntry(name: "Historical food", protein: 30, carbs: 45, fat: 15, date: oldDate)
        entry.reportedCalories = 457.5
        context.insert(entry)
        context.insert(MacroGoal())
        try context.save()
        let reread = ModelContext(container)
        let saved = try #require(reread.fetch(FetchDescriptor<MacroEntry>()).first)
        #expect(saved.calories == 457.5)
        #expect(saved.date == oldDate)
        let manual = MacroEntry(protein: 10, carbs: 20, fat: 5)
        #expect(manual.calories == 165)
        saved.name = "Edited"
        try reread.save()
        reread.delete(saved)
        try reread.save()
        #expect(try reread.fetch(FetchDescriptor<MacroEntry>()).isEmpty)
        #expect(try reread.fetch(FetchDescriptor<MacroGoal>()).count == 1)
        #expect(try reread.fetch(FetchDescriptor<SavedFood>()).count == 1)
    }

    @Test func networkResponses() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockFoodProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let service = FoodAPIService(session: session)
        MockFoodProtocol.status = 200
        MockFoodProtocol.body = Data(Self.fixture.utf8)
        let food = try await service.lookup(barcode: "012345678905")
        #expect(food.name == "Example food")
        #expect(MockFoodProtocol.request?.url?.path.contains("/api/v3.6/product/") == true)
        #expect(MockFoodProtocol.request?.value(forHTTPHeaderField: "User-Agent") == "Tally/1.0 (\(FoodAPIConfiguration.contact))")
        MockFoodProtocol.status = 404
        await #expect(throws: FoodAPIError.self) { try await service.lookup(barcode: "012345678905") }
        MockFoodProtocol.status = 429
        await #expect(throws: FoodAPIError.self) { try await service.lookup(barcode: "012345678905") }
        MockFoodProtocol.status = 200
        await #expect(throws: FoodAPIError.self) { try await service.lookup(barcode: "012345678905") }
        let timeoutService = FoodAPIService(session: session, contact: "test@example.invalid")
        MockFoodProtocol.failure = URLError(.timedOut)
        defer { MockFoodProtocol.failure = nil }
        await #expect(throws: FoodAPIError.self) { try await timeoutService.lookup(barcode: "012345678905") }
    }

    static let searchFixture = """
    {"products":[
      {"code":"012345678905","product_name":"Peanut butter","brands":"Example","image_front_url":"https://images.openfoodfacts.org/example.jpg"},
      {"code":"0012345678905","product_name":"Duplicate UPC"},
      {"code":"12345678","product_name":" ","product_name_en":"English name"},
      {"code":"invalid","product_name":"Invalid barcode"},
      {"product_name":"Missing barcode"}
    ]}
    """

    @Test func searchDecodingKeepsUsableUniqueIdentities() throws {
        let results = try FoodAPIService.decodeSearch(Data(Self.searchFixture.utf8))
        #expect(results.count == 2)
        #expect(results[0].barcode == "0012345678905")
        #expect(results[0].name == "Peanut butter")
        #expect(results[0].brand == "Example")
        #expect(results[0].imageURL?.scheme == "https")
        let unsafeImage = Self.searchFixture.replacingOccurrences(of: "https://images", with: "http://images")
        #expect(try FoodAPIService.decodeSearch(Data(unsafeImage.utf8))[0].imageURL == nil)
        #expect(results[1].name == "English name")
        #expect(try FoodAPIService.decodeSearch(Data(#"{"products":[]}"#.utf8)).isEmpty)
        #expect(throws: FoodAPIError.self) { try FoodAPIService.decodeSearch(Data("{}".utf8)) }
        #expect(throws: FoodAPIError.self) { try FoodAPIService.decodeSearch(Data("<html>Unavailable</html>".utf8)) }
    }

    @Test func submittedSearchEncodesQueryAndLoadsSelectedFood() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockFoodProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let service = FoodAPIService(session: session)
        MockFoodProtocol.status = 200
        MockFoodProtocol.failure = nil
        MockFoodProtocol.body = Data(Self.searchFixture.utf8)
        MockFoodProtocol.request = nil
        #expect(try await service.search(query: " \n ").isEmpty)
        #expect(MockFoodProtocol.request == nil)
        let results = try await service.search(query: "  PB & café + oats  ")
        let request = try #require(MockFoodProtocol.request)
        let url = try #require(request.url)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        #expect(url.path == "/cgi/search.pl")
        #expect(items?.first { $0.name == "search_terms" }?.value == "PB & café + oats")
        #expect(items?.first { $0.name == "page_size" }?.value == "25")
        #expect(items?.first { $0.name == "sort_by" }?.value == "popularity_key")
        let fields = items?.first { $0.name == "fields" }?.value?.split(separator: ",") ?? []
        #expect(fields.contains("popularity_key"))
        #expect(fields.contains("unique_scans_n"))
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "Tally/1.0 (\(FoodAPIConfiguration.contact))")
        MockFoodProtocol.body = Data(Self.fixture.utf8)
        let food = try await service.lookup(barcode: results[0].barcode)
        #expect(food.barcode == results[0].barcode)
        #expect(food.portions.first?.nutrition.isComplete == true)
    }

    @Test func searchRanksPopularityAndKeepsStableTies() throws {
        // Reproduce a live response whose products did not arrive in score order.
        let json = #"""
        {"products":[
          {"code":"12345678","product_name":"Popular food","popularity_key":"300","unique_scans_n":2},
          {"code":"87654321","product_name":"Less popular food","popularity_key":100,"unique_scans_n":999},
          {"code":"12345678","product_name":"Lower ranked duplicate","popularity_key":1},
          {"code":"00000001","product_name":"First tied food","popularity_key":300,"unique_scans_n":"10"},
          {"code":"00000002","product_name":"Second tied food","popularity_key":300,"unique_scans_n":10},
          {"code":"00000003","product_name":"Scan count fallback","unique_scans_n":50},
          {"code":"00000004","product_name":"Invalid score fallback","popularity_key":"NaN","unique_scans_n":20},
          {"code":"00000005","product_name":"Unranked food","popularity_key":-1}
        ]}
        """#
        let results = try FoodAPIService.decodeSearch(Data(json.utf8))
        #expect(results.map(\.name) == ["First tied food", "Second tied food", "Popular food",
                                     "Less popular food", "Scan count fallback", "Invalid score fallback", "Unranked food"])
    }

    @Test func searchRateLimitAndFailures() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockFoodProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        MockFoodProtocol.failure = nil
        MockFoodProtocol.status = 200
        MockFoodProtocol.body = Data(Self.searchFixture.utf8)
        let service = FoodAPIService(session: session)
        for _ in 0..<8 { _ = try await service.search(query: "oats") }
        do {
            _ = try await service.search(query: "oats")
            Issue.record("Expected the search rate guard to reject a ninth request")
        } catch FoodAPIError.rateLimited { }

        let failing = FoodAPIService(session: session)
        MockFoodProtocol.status = 503
        await #expect(throws: FoodAPIError.self) { try await failing.search(query: "oats") }
        MockFoodProtocol.status = 429
        await #expect(throws: FoodAPIError.self) { try await failing.search(query: "oats") }
        MockFoodProtocol.status = 200
        await #expect(throws: FoodAPIError.self) { try await failing.search(query: "oats") }
        let cancelled = FoodAPIService(session: session)
        MockFoodProtocol.failure = URLError(.cancelled)
        defer { MockFoodProtocol.failure = nil }
        await #expect(throws: CancellationError.self) { try await cancelled.search(query: "oats") }
    }
}

/// Serialized suite prevents concurrent mutation; no network requests leave this URLProtocol.
private final class MockFoodProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var body = Data()
    nonisolated(unsafe) static var failure: URLError?
    nonisolated(unsafe) static var request: URLRequest?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.request = request
        if let failure = Self.failure {
            client?.urlProtocol(self, didFailWithError: failure)
            return
        }
        guard let url = request.url, let response = HTTPURLResponse(url: url, statusCode: Self.status,
            httpVersion: nil, headerFields: ["Retry-After": "60"]) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
