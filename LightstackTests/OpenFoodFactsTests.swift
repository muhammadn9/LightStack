import XCTest
import CoreData
import Supabase
@testable import Lightstack

/// Nutrition phase 3: Open Food Facts parsing, rate limiting, cache, service, local-first barcode lookup,
/// persistence, Core Data v7 -> v8 and the wire format.
@MainActor
final class OpenFoodFactsTests: XCTestCase {

    private let user = UUID()

    // MARK: - Fixtures (shapes seen in the real database)

    private func parse(_ json: String) -> OpenFoodFactsProduct? {
        guard let data = json.data(using: .utf8),
              let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        return OpenFoodFactsParser.parseProduct(dict)
    }

    private let fullServing = """
    {"code":"0123456789012","product_name":"Greek Yogurt","brands":"Fage,Other","serving_size":"170 g","serving_quantity":170,
     "quantity":"500 g","image_front_small_url":"https://images.openfoodfacts.org/x.jpg",
     "nutriments":{"energy-kcal_100g":53,"energy-kcal_serving":90.1,"proteins_100g":10.6,"proteins_serving":18.0,
      "carbohydrates_100g":3.2,"carbohydrates_serving":5.44,"fat_100g":0.1,"fat_serving":0.17,
      "fiber_100g":0,"sugars_100g":3.2,"sugars_serving":5.44,"saturated-fat_100g":0,"sodium_100g":0.04,"sodium_serving":0.068}}
    """

    func testParsesPerServingValuesAndRounds() throws {
        let p = try XCTUnwrap(parse(fullServing))
        XCTAssertEqual(p.barcode, "0123456789012")
        XCTAssertEqual(p.name, "Greek Yogurt")
        XCTAssertEqual(p.brand, "Fage", "first brand only")
        XCTAssertTrue(p.hasServingSize)
        XCTAssertEqual(p.servingLabel, "170 g")
        XCTAssertEqual(p.servingUnit, "g")
        XCTAssertEqual(p.servingAmount, 170)
        XCTAssertEqual(p.servingGrams, 170)
        XCTAssertEqual(p.nutrients.kcal, 90)
        XCTAssertEqual(p.nutrients.protein, 18)
        XCTAssertEqual(p.nutrients.carbs, 5.4)
        XCTAssertEqual(p.nutrients.fat, 0.2)
        XCTAssertEqual(p.nutrients.micros[.sugar], 5.4)
        XCTAssertEqual(p.nutrients.micros[.sodium], 68, "sodium g -> mg")
        XCTAssertEqual(p.quantityText, "500 g")
        XCTAssertNotNil(p.imageURL)
        XCTAssertTrue(p.warnings.isEmpty)
    }

    func testMissingServingFallsBackToPer100g() throws {
        let p = try XCTUnwrap(parse("""
        {"code":"5449000000996","product_name":"Cola","brands":"Brand","nutriments":{"energy-kcal_100g":42,"proteins_100g":0,"carbohydrates_100g":10.6,"fat_100g":0}}
        """))
        XCTAssertFalse(p.hasServingSize)
        XCTAssertEqual(p.servingLabel, "100 g")
        XCTAssertEqual(p.servingAmount, 100)
        XCTAssertEqual(p.nutrients.kcal, 42)
        XCTAssertTrue(p.warnings.contains(.per100Only))
    }

    func testServingValuesComputedFromPer100WhenOnlyThatExists() throws {
        let p = try XCTUnwrap(parse("""
        {"code":"5449000000996","product_name":"Bar","serving_size":"40 g","serving_quantity":"40",
         "nutriments":{"energy-kcal_100g":"450","proteins_100g":"10","carbohydrates_100g":"50","fat_100g":"20"}}
        """))
        XCTAssertEqual(p.servingAmount, 40)
        XCTAssertEqual(p.nutrients.kcal, 180)
        XCTAssertEqual(p.nutrients.protein, 4)
        XCTAssertEqual(p.nutrients.fat, 8)
    }

    func testKilojouleOnlyEnergyIsConverted() throws {
        let p = try XCTUnwrap(parse("""
        {"code":"4000000000017","product_name":"Muesli","nutriments":{"energy-kj_100g":1500,"proteins_100g":10,"carbohydrates_100g":60,"fat_100g":8}}
        """))
        XCTAssertEqual(p.nutrients.kcal, (1500 / 4.184).rounded())
        XCTAssertTrue(p.warnings.contains(.kcalFromKilojoules))
        // Plain `energy_100g` is kJ too.
        let q = try XCTUnwrap(parse("""
        {"code":"4000000000024","product_name":"Rice","nutriments":{"energy_100g":1000,"proteins_100g":7,"carbohydrates_100g":78,"fat_100g":1}}
        """))
        XCTAssertEqual(q.nutrients.kcal, (1000 / 4.184).rounded())
    }

    func testKcalIsPreferredOverKilojoules() throws {
        let p = try XCTUnwrap(parse("""
        {"code":"4000000000031","product_name":"X","nutriments":{"energy-kcal_100g":100,"energy-kj_100g":9999,"proteins_100g":1,"carbohydrates_100g":1,"fat_100g":1}}
        """))
        XCTAssertEqual(p.nutrients.kcal, 100)
        XCTAssertFalse(p.warnings.contains(.kcalFromKilojoules))
    }

    func testSaltOnlyBecomesSodium() throws {
        let p = try XCTUnwrap(parse("""
        {"code":"4000000000048","product_name":"Crisps","nutriments":{"energy-kcal_100g":520,"proteins_100g":6,"carbohydrates_100g":50,"fat_100g":32,"salt_100g":1.5}}
        """))
        XCTAssertEqual(p.nutrients.micros[.sodium], 600, "1.5 g salt = 600 mg sodium")
    }

    func testStringNumbersAndCommaDecimals() throws {
        let p = try XCTUnwrap(parse("""
        {"code":"4000000000055","product_name":"Soup","serving_quantity":"250","serving_size":"250 ml","quantity":"1 L",
         "nutriments":{"energy-kcal_serving":"62,5","proteins_serving":"2,1","carbohydrates_serving":"9","fat_serving":"1.8 g"}}
        """))
        XCTAssertEqual(p.servingUnit, "ml")
        XCTAssertNil(p.servingGrams, "millilitre servings have no gram weight")
        XCTAssertEqual(p.nutrients.kcal, 63)       // 62.5 rounds half away from zero
        XCTAssertEqual(p.nutrients.protein, 2.1)
        XCTAssertEqual(p.nutrients.fat, 1.8)
    }

    func testMissingKcalIsDerivedFromMacrosAndFlagged() throws {
        let p = try XCTUnwrap(parse("""
        {"code":"4000000000062","product_name":"Shake","nutriments":{"proteins_100g":10,"carbohydrates_100g":10,"fat_100g":10}}
        """))
        XCTAssertEqual(p.nutrients.kcal, 170)
        XCTAssertTrue(p.warnings.contains(.kcalFromMacros))
    }

    func testPartialMacrosAreFlagged() throws {
        let p = try XCTUnwrap(parse("""
        {"code":"4000000000079","product_name":"Candy","nutriments":{"energy-kcal_100g":400,"carbohydrates_100g":90}}
        """))
        XCTAssertEqual(p.nutrients.protein, 0)
        XCTAssertTrue(p.warnings.contains(.missingMacros))
    }

    func testUnusableProductsAreSkipped() {
        XCTAssertNil(parse(#"{"code":"4000000000086","product_name":"Nothing","nutriments":{}}"#), "no kcal and no macros")
        XCTAssertNil(parse(#"{"code":"4000000000086","product_name":"  ","nutriments":{"energy-kcal_100g":10}}"#), "no name")
        XCTAssertNil(parse(#"{"product_name":"No code","nutriments":{"energy-kcal_100g":10}}"#), "no barcode")
        XCTAssertNil(parse(#"{"code":"abc","product_name":"Bad code","nutriments":{"energy-kcal_100g":10}}"#))
        XCTAssertNil(parse(#"{"code":"4000000000093","product_name":"Neg","nutriments":{"energy-kcal_100g":-5}}"#))
    }

    func testProductResponseStatuses() throws {
        let ok = #"{"code":"0123456789012","status":1,"product":{"product_name":"Yogurt","nutriments":{"energy-kcal_100g":50,"proteins_100g":5,"carbohydrates_100g":5,"fat_100g":1}}}"#
        XCTAssertEqual(try OpenFoodFactsParser.parseProductResponse(Data(ok.utf8)).barcode, "0123456789012", "code taken from the envelope")
        XCTAssertThrowsError(try OpenFoodFactsParser.parseProductResponse(Data(#"{"code":"1","status":0,"status_verbose":"product not found"}"#.utf8))) {
            XCTAssertEqual($0 as? OpenFoodFactsError, .notFound)
        }
        XCTAssertThrowsError(try OpenFoodFactsParser.parseProductResponse(Data("<html>".utf8))) {
            XCTAssertEqual($0 as? OpenFoodFactsError, .badData)
        }
        let noNutrition = #"{"code":"4000000000086","status":1,"product":{"product_name":"Empty","nutriments":{}}}"#
        XCTAssertThrowsError(try OpenFoodFactsParser.parseProductResponse(Data(noNutrition.utf8))) {
            XCTAssertEqual($0 as? OpenFoodFactsError, .badData)
        }
    }

    func testSearchResponseSkipsBadAndDuplicateProducts() throws {
        let json = """
        {"count":4,"hits":[
          {"code":"4000000000017","product_name":"A","nutriments":{"energy-kcal_100g":10,"proteins_100g":1,"carbohydrates_100g":1,"fat_100g":1}},
          {"code":"4000000000017","product_name":"A again","nutriments":{"energy-kcal_100g":10}},
          {"code":"4000000000024","product_name":"","nutriments":{"energy-kcal_100g":10}},
          {"code":"4000000000031","product_name":"B","nutriments":{}}
        ]}
        """
        XCTAssertEqual(try OpenFoodFactsParser.parseSearchResponse(Data(json.utf8)).map(\.name), ["A"])
        XCTAssertThrowsError(try OpenFoodFactsParser.parseSearchResponse(Data(#"{"nope":1}"#.utf8)))
    }

    func testSearchALiciousHitsParse() throws {
        let json = """
        {"hits":[
          {"code":"9300650450271","brands":["Oreo"],"nutriments":{"carbohydrates_100g":70.1754,"energy-kcal_100g":483.8596,"fat_100g":20,"proteins_100g":4.2105,"salt_100g":1.28947375,"sugars_100g":38.5965},"product_name":"Oreo strawberry"},
          {"code":"3017620422003","brands":["Nutella","Ferrero"],"nutriments":{"carbohydrates_100g":57.5,"energy-kj_100g":2252,"fat_100g":30.9,"proteins_100g":6.3},"product_name":"Spread"}
        ],"page":1,"page_size":20,"page_count":2}
        """
        let items = try OpenFoodFactsParser.parseSearchResponse(Data(json.utf8))
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].brand, "Oreo")
        XCTAssertEqual(items[0].nutrients.kcal, 484)
        XCTAssertTrue(items[0].warnings.contains(.per100Only))
        XCTAssertEqual(items[1].brand, "Nutella")
        XCTAssertEqual(items[1].nutrients.kcal, 538)
        XCTAssertTrue(items[1].warnings.contains(.kcalFromKilojoules))
    }

    func testSearchHtmlBodyAndServerErrorsAreUnavailable() async {
        XCTAssertThrowsError(try OpenFoodFactsParser.parseSearchResponse(Data("<html>bot check</html>".utf8))) {
            XCTAssertEqual($0 as? OpenFoodFactsError, .unavailable)
        }
        let t = FakeTransport()
        let service = makeService(t)
        t.handler = { _ in (Data("<html>".utf8), 503, [:]) }
        await assertThrows(OpenFoodFactsError.unavailable) { _ = try await service.search(query: "html") }
        t.handler = { _ in (Data("<html>".utf8), 200, [:]) }
        await assertThrows(OpenFoodFactsError.unavailable) { _ = try await service.search(query: "html200") }
    }

    func testBrandsAcceptStringOrArray() throws {
        let nut = #""nutriments":{"energy-kcal_100g":10,"proteins_100g":1,"carbohydrates_100g":1,"fat_100g":1}"#
        let a = try XCTUnwrap(OpenFoodFactsParser.parseProduct(try XCTUnwrap(JSONSerialization.jsonObject(with: Data("{\"code\":\"4000000000017\",\"product_name\":\"A\",\"brands\":\"X, Y\",\(nut)}".utf8)) as? [String: Any])))
        XCTAssertEqual(a.brand, "X")
        let b = try XCTUnwrap(OpenFoodFactsParser.parseProduct(try XCTUnwrap(JSONSerialization.jsonObject(with: Data("{\"code\":\"4000000000017\",\"product_name\":\"A\",\"brands\":[\"Z\"],\(nut)}".utf8)) as? [String: Any])))
        XCTAssertEqual(b.brand, "Z")
    }

    func testProductCodableRoundTrip() throws {
        let p = try XCTUnwrap(parse(fullServing))
        let data = try JSONEncoder().encode(p)
        XCTAssertEqual(try JSONDecoder().decode(OpenFoodFactsProduct.self, from: data), p)
    }

    // MARK: - Barcode helpers

    func testBarcodeNormalizeAndVariants() {
        XCTAssertEqual(Barcode.normalized(" 0123456789012 "), "0123456789012")
        XCTAssertNil(Barcode.normalized("12345"))
        XCTAssertNil(Barcode.normalized("12345678abcde"))
        XCTAssertEqual(Barcode.variants("123456789012"), ["123456789012", "0123456789012"])
        XCTAssertEqual(Barcode.variants("0123456789012"), ["0123456789012", "123456789012"])
    }

    // MARK: - Rate limiter

    private final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var t = Date(timeIntervalSince1970: 1_000_000)
        private var _slept: [TimeInterval] = []
        var now: Date { lock.withLock { t } }
        var slept: [TimeInterval] { lock.withLock { _slept } }
        func advance(_ s: TimeInterval) { lock.withLock { t = t.addingTimeInterval(s) } }
        func sleep(_ s: TimeInterval) { lock.withLock { _slept.append(s); t = t.addingTimeInterval(s) } }
    }

    func testLimiterAllowsBurstThenThrottles() async throws {
        let clock = Clock()
        let limiter = OpenFoodFactsRateLimiter(maxRequests: 3, per: 60, maxWait: 5,
                                               now: { clock.now }, sleep: { clock.sleep($0) })
        for _ in 0..<3 { try await limiter.acquire() }
        XCTAssertTrue(clock.slept.isEmpty)
        // 4th request would wait ~60 s: longer than maxWait, so it is refused.
        do { try await limiter.acquire(); XCTFail("expected rateLimited") }
        catch { XCTAssertEqual(error as? OpenFoodFactsError, .rateLimited) }
        // After the window passes it works again.
        clock.advance(61)
        try await limiter.acquire()
    }

    func testLimiterWaitsWhenTheWaitIsShort() async throws {
        let clock = Clock()
        let limiter = OpenFoodFactsRateLimiter(maxRequests: 2, per: 10, maxWait: 5,
                                               now: { clock.now }, sleep: { clock.sleep($0) })
        try await limiter.acquire()
        clock.advance(6)
        try await limiter.acquire()
        clock.advance(1)            // oldest request is 7 s old: 3 s to wait
        try await limiter.acquire()
        XCTAssertEqual(clock.slept.count, 1)
        XCTAssertEqual(try XCTUnwrap(clock.slept.first), 3, accuracy: 0.01)
    }

    func testLimiterHonoursServerBlock() async throws {
        let clock = Clock()
        let limiter = OpenFoodFactsRateLimiter(maxRequests: 10, per: 60, now: { clock.now }, sleep: { clock.sleep($0) })
        await limiter.block(for: 30)
        do { try await limiter.acquire(); XCTFail("expected rateLimited") }
        catch { XCTAssertEqual(error as? OpenFoodFactsError, .rateLimited) }
        clock.advance(31)
        try await limiter.acquire()
    }

    // MARK: - Cache

    func testCacheExpiresBarcodesAfter30DaysAndSearchesAfter10Minutes() throws {
        let clock = Clock()
        let cache = OpenFoodFactsCache(fileURL: nil, now: { clock.now })
        let product = try XCTUnwrap(parse(fullServing))
        cache.store(product)
        cache.store(search: "Greek  Yogurt", results: [product])
        XCTAssertEqual(cache.product(barcode: product.barcode), product)
        XCTAssertEqual(cache.search("greek yogurt")?.count, 1, "key ignores case and extra spaces")
        clock.advance(11 * 60)
        XCTAssertNil(cache.search("greek yogurt"))
        XCTAssertNotNil(cache.product(barcode: product.barcode))
        clock.advance(31 * 86_400)
        XCTAssertNil(cache.product(barcode: product.barcode))
    }

    func testCachePersistsToDisk() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("off-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let product = try XCTUnwrap(parse(fullServing))
        OpenFoodFactsCache(fileURL: url).store(product)
        XCTAssertEqual(OpenFoodFactsCache(fileURL: url).product(barcode: product.barcode), product)
    }

    func testSearchResultsWarmTheBarcodeCache() throws {
        let cache = OpenFoodFactsCache(fileURL: nil)
        let product = try XCTUnwrap(parse(fullServing))
        cache.store(search: "yogurt", results: [product])
        XCTAssertEqual(cache.product(barcode: product.barcode), product)
    }

    // MARK: - Live service over a fake transport

    private final class FakeTransport: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var requests: [URLRequest] = []
        var handler: @Sendable (URLRequest) async throws -> (Data, Int, [String: String]) = { _ in (Data(), 200, [:]) }
        var delay: TimeInterval = 0
        func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            lock.withLock { requests.append(request) }
            if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            let (data, status, headers) = try await handler(request)
            guard let url = request.url,
                  let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers) else {
                throw URLError(.badServerResponse)
            }
            return (data, response)
        }
        var count: Int { lock.withLock { requests.count } }
    }

    private func makeService(_ transport: FakeTransport, cache: OpenFoodFactsCache = OpenFoodFactsCache(fileURL: nil),
                             search: OpenFoodFactsRateLimiter = OpenFoodFactsRateLimiter(maxRequests: 8, per: 60)) -> OpenFoodFactsService {
        OpenFoodFactsService(transport: { try await transport.send($0) }, cache: cache,
                             userAgent: "LightStack/1.0 (iOS; nutrition)", searchLimiter: search)
    }

    private let productJSON = #"{"code":"0123456789012","status":1,"product":{"product_name":"Yogurt","nutriments":{"energy-kcal_100g":50,"proteins_100g":5,"carbohydrates_100g":5,"fat_100g":1}}}"#
    private let searchJSON = #"{"hits":[{"code":"4000000000017","product_name":"A","nutriments":{"energy-kcal_100g":10,"proteins_100g":1,"carbohydrates_100g":1,"fat_100g":1}}]}"#

    func testRequestsCarryUserAgentAndNoPersonalData() async throws {
        let t = FakeTransport()
        t.handler = { [productJSON] _ in (Data(productJSON.utf8), 200, [:]) }
        _ = try await makeService(t).product(barcode: "0123456789012")
        let request = try XCTUnwrap(t.requests.first)
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "LightStack/1.0 (iOS; nutrition)")
        XCTAssertEqual(request.url?.host, "world.openfoodfacts.org")
        XCTAssertEqual(request.url?.path, "/api/v2/product/0123456789012.json")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
        XCTAssertTrue(request.url?.query?.contains("fields=") ?? false)
        XCTAssertTrue(OpenFoodFactsService.defaultUserAgent().hasPrefix("LightStack/"))
        XCTAssertTrue(OpenFoodFactsService.defaultUserAgent().hasSuffix("(iOS; nutrition)"))
    }

    func testSearchRequestShape() async throws {
        let t = FakeTransport()
        t.handler = { [searchJSON] _ in (Data(searchJSON.utf8), 200, [:]) }
        let results = try await makeService(t).search(query: "  greek yogurt ")
        XCTAssertEqual(results.count, 1)
        let url = try XCTUnwrap(t.requests.first?.url)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(url.host, "search.openfoodfacts.org")
        XCTAssertEqual(url.path, "/search")
        XCTAssertEqual(items.first { $0.name == "q" }?.value, "greek yogurt")
        XCTAssertEqual(items.first { $0.name == "page_size" }?.value, "20")
    }

    func testBarcodeIsCachedAndInvalidCodesNeverHitTheNetwork() async throws {
        let t = FakeTransport()
        t.handler = { [productJSON] _ in (Data(productJSON.utf8), 200, [:]) }
        let service = makeService(t)
        _ = try await service.product(barcode: "0123456789012")
        _ = try await service.product(barcode: "0123456789012")
        XCTAssertEqual(t.count, 1, "second lookup comes from the cache")
        do { _ = try await service.product(barcode: "123"); XCTFail() } catch { XCTAssertEqual(error as? OpenFoodFactsError, .notFound) }
        XCTAssertEqual(t.count, 1)
        let tiny = try await service.search(query: "a")
        XCTAssertEqual(tiny.count, 0)
        XCTAssertEqual(t.count, 1, "one-letter searches never hit the network")
    }

    func testErrorMapping() async {
        let t = FakeTransport()
        let service = makeService(t)
        t.handler = { _ in (Data(), 404, [:]) }
        await assertThrows(OpenFoodFactsError.notFound) { _ = try await service.product(barcode: "0123456789012") }
        t.handler = { _ in (Data(), 503, [:]) }
        await assertThrows(OpenFoodFactsError.unavailable) { _ = try await service.product(barcode: "0123456789013") }
        t.handler = { _ in (Data("garbage".utf8), 200, [:]) }
        await assertThrows(OpenFoodFactsError.badData) { _ = try await service.product(barcode: "0123456789014") }
        t.handler = { _ in throw URLError(.notConnectedToInternet) }
        await assertThrows(OpenFoodFactsError.offline) { _ = try await service.product(barcode: "0123456789015") }
        t.handler = { _ in throw URLError(.timedOut) }
        await assertThrows(OpenFoodFactsError.offline) { _ = try await service.search(query: "timeout") }
    }

    func testHTTP429BlocksFurtherRequests() async {
        let t = FakeTransport()
        t.handler = { _ in (Data(), 429, ["Retry-After": "30"]) }
        let service = makeService(t)
        await assertThrows(OpenFoodFactsError.rateLimited) { _ = try await service.search(query: "oreo") }
        let after = t.count
        await assertThrows(OpenFoodFactsError.rateLimited) { _ = try await service.search(query: "milk") }
        XCTAssertEqual(t.count, after, "blocked locally, no second request")
    }

    func testClientSideSearchThrottle() async {
        let t = FakeTransport()
        t.handler = { [searchJSON] _ in (Data(searchJSON.utf8), 200, [:]) }
        let service = makeService(t, search: OpenFoodFactsRateLimiter(maxRequests: 2, per: 60, maxWait: 1))
        _ = try? await service.search(query: "one")
        _ = try? await service.search(query: "two")
        await assertThrows(OpenFoodFactsError.rateLimited) { _ = try await service.search(query: "three") }
        XCTAssertEqual(t.count, 2)
    }

    func testIdenticalInFlightSearchesCoalesce() async throws {
        let t = FakeTransport()
        t.delay = 0.2
        t.handler = { [searchJSON] _ in (Data(searchJSON.utf8), 200, [:]) }
        let service = makeService(t)
        async let a = service.search(query: "oreo")
        async let b = service.search(query: "Oreo")
        let (ra, rb) = try await (a, b)
        XCTAssertEqual(ra, rb)
        XCTAssertEqual(t.count, 1, "one request served both callers")
    }

    private func assertThrows(_ expected: OpenFoodFactsError, _ body: () async throws -> Void,
                              file: StaticString = #filePath, line: UInt = #line) async {
        do { try await body(); XCTFail("expected \(expected)", file: file, line: line) }
        catch { XCTAssertEqual(error as? OpenFoodFactsError, expected, file: file, line: line) }
    }

    // MARK: - Repository, view model, persistence

    private struct Device {
        let stack: OutboxTestStack
        let repo: NutritionRepository
        var storage: LocalStorageService { stack.storage }
    }

    private func makeDevice(remote: FakeRemote = FakeRemote()) -> Device {
        let stack = OutboxTestStack(userId: user, remote: remote)
        return Device(stack: stack, repo: NutritionRepository(localStorage: stack.storage, offlineQueueManager: stack.queue))
    }

    private func makeViewModel(_ d: Device, service: OpenFoodFactsServicing?, debounce: TimeInterval = 0) -> NutritionViewModel {
        let uid = user
        return NutritionViewModel(repository: d.repo, userIdProvider: { uid }, foodDatabase: service, brandedDebounce: debounce)
    }

    private func waitUntil(timeout: TimeInterval = 3, _ condition: () -> Bool) async {
        let end = Date().addingTimeInterval(timeout)
        while !condition(), Date() < end { try? await Task.sleep(nanoseconds: 10_000_000) }
    }

    func testSavedBrandedFoodKeepsSourceBarcodeAndDedupes() throws {
        let d = makeDevice()
        let product = try XCTUnwrap(FakeOpenFoodFactsService.catalog.first)
        let saved = d.repo.saveBrandedFood(product, userId: user)
        XCTAssertEqual(saved.source, .openFoodFacts)
        XCTAssertEqual(saved.barcode, "0123456789012")
        XCTAssertEqual(saved.brand, "Fage")
        XCTAssertEqual(saved.servingLabel, "170 g")
        XCTAssertEqual(saved.servingGrams, 170)
        XCTAssertEqual(saved.nutrients.kcal, 90)
        let reloaded = try XCTUnwrap(d.repo.food(id: saved.id))
        XCTAssertEqual(reloaded.source, .openFoodFacts)
        XCTAssertEqual(reloaded.barcode, "0123456789012")
        // Saving it again returns the same food.
        XCTAssertEqual(d.repo.saveBrandedFood(product, userId: user).id, saved.id)
        XCTAssertEqual(d.repo.searchFoods(userId: user, query: "yogurt").count, 1)
        // UPC-A spelling of the same code finds it too.
        XCTAssertEqual(d.repo.food(barcode: "123456789012", userId: user)?.id, saved.id)
    }

    func testLogBrandedFoodAppearsInRecentAndTotals() throws {
        let d = makeDevice()
        let vm = makeViewModel(d, service: FakeOpenFoodFactsService())
        let product = try XCTUnwrap(FakeOpenFoodFactsService.catalog.first)
        let saved = try XCTUnwrap(vm.saveBrandedFood(product, logServings: 2))
        XCTAssertEqual(vm.recentFoods().map(\.id), [saved.id])
        let day = d.repo.dailyNutrition(userId: user, on: Date())
        XCTAssertEqual(day.totals.kcal, 180)
        XCTAssertEqual(day.entries.first?.source, .saved)
        XCTAssertGreaterThan(vm.foodsVersion, 0)
    }

    func testBarcodeLookupIsLocalFirst() async throws {
        let d = makeDevice()
        let fake = FakeOpenFoodFactsService()
        let vm = makeViewModel(d, service: fake)
        // 1st scan: remote.
        let first = await vm.lookupBarcode("0123456789012")
        guard case .remote(let product) = first else { return XCTFail("expected remote, got \(first)") }
        XCTAssertEqual(fake.barcodeCalls.count, 1)
        _ = vm.saveBrandedFood(product)
        // 2nd scan of the same code: local food, no network.
        let second = await vm.lookupBarcode("0123456789012")
        guard case .local(let food) = second else { return XCTFail("expected local, got \(second)") }
        XCTAssertEqual(food.barcode, "0123456789012")
        XCTAssertEqual(fake.barcodeCalls.count, 1, "no second network call")
        // UPC-A spelling hits the local food as well.
        if case .local = await vm.lookupBarcode("123456789012") {} else { XCTFail("UPC-A spelling should match locally") }
        XCTAssertEqual(fake.barcodeCalls.count, 1)
    }

    func testBarcodeLookupOutcomes() async {
        let d = makeDevice()
        let fake = FakeOpenFoodFactsService()
        let vm = makeViewModel(d, service: fake)
        let missing = await vm.lookupBarcode("0000000000000")
        XCTAssertEqual(missing, .notFound)
        let junk = await vm.lookupBarcode("12")
        XCTAssertEqual(junk, .notFound)
        fake.error = .offline
        let offline = await vm.lookupBarcode("0123456789012")
        XCTAssertEqual(offline, .failed(OpenFoodFactsError.offline.message))
        let unconfigured = await makeViewModel(d, service: nil).lookupBarcode("0123456789012")
        if case .failed = unconfigured {} else { XCTFail("expected failed") }
    }

    func testBrandedSearchStates() async {
        let d = makeDevice()
        let fake = FakeOpenFoodFactsService()
        let vm = makeViewModel(d, service: fake)
        XCTAssertEqual(vm.brandedState, .idle)
        vm.searchBranded("greek yogurt")
        XCTAssertEqual(vm.brandedState, .loading)
        await waitUntil { if case .results = vm.brandedState { return true }; return false }
        guard case .results(let found) = vm.brandedState else { return XCTFail("got \(vm.brandedState)") }
        XCTAssertEqual(found.count, 2)

        vm.searchBranded("zzzzqq")
        await waitUntil { vm.brandedState == .empty }
        XCTAssertEqual(vm.brandedState, .empty)

        fake.error = .rateLimited
        vm.searchBranded("oreo")
        await waitUntil { if case .error = vm.brandedState { return true }; return false }
        XCTAssertEqual(vm.brandedState, .error(OpenFoodFactsError.rateLimited.message))

        vm.searchBranded("o")
        XCTAssertEqual(vm.brandedState, .idle, "too short resets")
        vm.cancelBrandedSearch()
        XCTAssertEqual(vm.brandedState, .idle)
    }

    func testBrandedSearchDebouncesKeystrokes() async {
        let d = makeDevice()
        let fake = FakeOpenFoodFactsService()
        let vm = makeViewModel(d, service: fake, debounce: 0.15)
        for q in ["or", "ore", "oreo"] { vm.searchBranded(q) }
        await waitUntil { if case .results = vm.brandedState { return true }; return false }
        XCTAssertEqual(fake.searchCalls, ["oreo"], "only the last query reached the service")
    }

    func testStaleSearchResultsNeverOverwriteNewerOnes() async {
        let d = makeDevice()
        let fake = FakeOpenFoodFactsService()
        fake.delay = 0.2
        let vm = makeViewModel(d, service: fake)
        vm.searchBranded("greek")
        try? await Task.sleep(nanoseconds: 50_000_000)
        fake.delay = 0
        vm.searchBranded("oreo")
        try? await Task.sleep(nanoseconds: 400_000_000)
        guard case .results(let found) = vm.brandedState else { return XCTFail("got \(vm.brandedState)") }
        XCTAssertTrue(found.allSatisfy { $0.name.lowercased().contains("oreo") })
    }

    func testFakeServiceDeterministicFixtures() async throws {
        let fake = FakeOpenFoodFactsService()
        let yogurt = try await fake.search(query: "greek yogurt")
        let oreo = try await fake.search(query: "oreo")
        let found = try await fake.product(barcode: "0123456789012")
        XCTAssertEqual(yogurt.count, 2)
        XCTAssertEqual(oreo.count, 2)
        XCTAssertEqual(found.name, "Total 0% Greek Yogurt")
        do { _ = try await fake.product(barcode: "0000000000000"); XCTFail() }
        catch { XCTAssertEqual(error as? OpenFoodFactsError, .notFound) }
    }

    // MARK: - Wire format and sync

    private struct AnyEncodable: Encodable {
        let wrapped: Encodable
        func encode(to encoder: Encoder) throws { try wrapped.encode(to: encoder) }
    }

    private func json(_ food: NutritionFood, forCloud: Bool) throws -> [String: Any] {
        let data = try JSONEncoder().encode(forCloud ? AnyEncodable(wrapped: food.cloudRow()) : AnyEncodable(wrapped: food))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testWireFormatCarriesBarcodeAndSource() throws {
        var food = NutritionFood.make(userId: user, name: "Y", nutrients: NutrientValues(kcal: 1, protein: 1, carbs: 1, fat: 1),
                                      source: .openFoodFacts, barcode: "0123456789012")
        for forCloud in [true, false] {
            let obj = try json(food, forCloud: forCloud)
            XCTAssertEqual(obj["barcode"] as? String, "0123456789012")
            XCTAssertEqual(obj["source"] as? String, "off")
        }
        // No barcode is an explicit null, never omitted.
        food.barcode = nil; food.source = .quick
        let obj = try json(food, forCloud: true)
        XCTAssertTrue(obj["barcode"] is NSNull)
        // Round trip, and an old server row without the column still decodes.
        let decoded = try JSONDecoder().decode(NutritionFood.self, from: JSONEncoder().encode(AnyEncodable(wrapped: food)))
        XCTAssertNil(decoded.barcode)
        var old = try json(food, forCloud: false)
        old.removeValue(forKey: "barcode")
        let oldData = try JSONSerialization.data(withJSONObject: old)
        XCTAssertNil(try JSONDecoder().decode(NutritionFood.self, from: oldData).barcode)
    }

    func testBrandedFoodUploadsAndRestoresWithBarcode() async throws {
        let remote = FakeRemote()
        let d = makeDevice(remote: remote)
        let product = try XCTUnwrap(FakeOpenFoodFactsService.catalog.first)
        let saved = d.repo.saveBrandedFood(product, userId: user)
        await d.stack.flushAll()
        let uploaded = try XCTUnwrap(remote.foods[saved.id])
        XCTAssertEqual(uploaded.barcode, "0123456789012")
        XCTAssertEqual(uploaded.source, .openFoodFacts)
    }

    func testMissingColumnAndSourceCheckRetryInsteadOfDeadLettering() async {
        XCTAssertEqual(SyncErrorClassifier.classify(PostgrestError(code: "PGRST204", message: "Could not find the 'barcode' column"), opType: .upsertFood), .dependency)
        XCTAssertEqual(SyncErrorClassifier.classify(PostgrestError(code: "42703", message: "column does not exist"), opType: .upsertFood), .dependency)
        XCTAssertEqual(SyncErrorClassifier.classify(PostgrestError(code: "23514", message: "foods_source_check"), opType: .upsertFood), .dependency)
        XCTAssertEqual(SyncErrorClassifier.classify(PostgrestError(code: "23514", message: "check"), opType: .upsertFoodEntry), .permanent)

        let remote = FakeRemote()
        remote.script = { type, _ in
            type == .upsertFood ? PostgrestError(code: "PGRST204", message: "Could not find the 'barcode' column") : nil
        }
        let d = makeDevice(remote: remote)
        let product = FakeOpenFoodFactsService.catalog[0]
        _ = d.repo.saveBrandedFood(product, userId: user)
        let other = d.repo.quickAdd(userId: user, on: Date(), name: "Bar", nutrients: NutrientValues(kcal: 1, protein: 1, carbs: 1, fat: 1))
        await d.stack.flushAll()
        XCTAssertNotNil(remote.foodEntries[other.id], "other writes still flow")
        let failed = await d.stack.queue.failedOperations()
        XCTAssertTrue(failed.isEmpty)
        let queued = await d.stack.queue.queuedOperations().map(\.type)
        XCTAssertTrue(queued.contains(.upsertFood), "food stays queued until the migration is applied")
    }

    // MARK: - Core Data v7 -> v8

    func testMigratesV7StoreToV8AddsFoodBarcodeAndKeepsFoods() throws {
        let bundle = Bundle(for: LocalStorageService.self)
        let v7URL = try XCTUnwrap(bundle.url(forResource: "Lightstack 7", withExtension: "mom", subdirectory: "Lightstack.momd"))
        let v8URL = try XCTUnwrap(bundle.url(forResource: "Lightstack 8", withExtension: "mom", subdirectory: "Lightstack.momd"))
        let v7Model = try XCTUnwrap(NSManagedObjectModel(contentsOf: v7URL))
        let v8Model = try XCTUnwrap(NSManagedObjectModel(contentsOf: v8URL))
        XCTAssertNil(v7Model.entitiesByName["CDFood"]?.attributesByName["barcode"])
        XCTAssertNotNil(v8Model.entitiesByName["CDFood"]?.attributesByName["barcode"])

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let storeURL = dir.appendingPathComponent("Lightstack.sqlite")
        let foodId = UUID()
        do {
            let coordinator = NSPersistentStoreCoordinator(managedObjectModel: v7Model)
            let store = try coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL, options: nil)
            let ctx = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
            ctx.persistentStoreCoordinator = coordinator
            try ctx.performAndWait {
                let e = NSEntityDescription.insertNewObject(forEntityName: "CDFood", into: ctx)
                e.setValue(foodId, forKey: "id"); e.setValue(UUID(), forKey: "userId")
                e.setValue("Oats", forKey: "name"); e.setValue(150.0, forKey: "kcal")
                e.setValue("quick", forKey: "source")
                e.setValue(Date(), forKey: "createdAt"); e.setValue(Date(), forKey: "updatedAt")
                try ctx.save()
            }
            try coordinator.remove(store)
        }

        let container = NSPersistentContainer(name: "Lightstack")
        let desc = NSPersistentStoreDescription(url: storeURL)
        desc.shouldMigrateStoreAutomatically = true
        desc.shouldInferMappingModelAutomatically = true
        container.persistentStoreDescriptions = [desc]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        XCTAssertNil(loadError, "Migration failed: \(String(describing: loadError))")

        let ctx = container.viewContext
        let migrated = try XCTUnwrap(ctx.fetch(CDFood.fetchRequest() as NSFetchRequest<CDFood>).first)
        XCTAssertEqual(migrated.id, foodId)
        XCTAssertEqual(migrated.name, "Oats")
        XCTAssertEqual(migrated.kcal, 150)
        XCTAssertNil(migrated.barcode, "existing foods have no barcode")
        migrated.barcode = "0123456789012"
        try ctx.save()
        XCTAssertEqual(try ctx.fetch(CDFood.fetchRequest() as NSFetchRequest<CDFood>).first?.barcode, "0123456789012")
    }
}
