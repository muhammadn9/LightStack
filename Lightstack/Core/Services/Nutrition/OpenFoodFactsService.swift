import Foundation

// MARK: - Protocol

/// Branded food search and barcode lookup. Implementations never throw anything but `OpenFoodFactsError`
/// (or `CancellationError` when the caller's task is cancelled).
protocol OpenFoodFactsServicing: Sendable {
    /// One product by barcode. Throws `.notFound` when the code is unknown or is not a barcode.
    func product(barcode: String) async throws -> OpenFoodFactsProduct
    /// Text search. A blank or one-letter query returns [] without touching the network.
    func search(query: String) async throws -> [OpenFoodFactsProduct]
}

// MARK: - Barcode helpers

enum Barcode {
    /// Digits only, 8-14 long (EAN-8, UPC-A, EAN-13, GTIN-14). nil when `raw` is not a barcode.
    static func normalized(_ raw: String) -> String? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (8...14).contains(t.count), t.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return t
    }

    /// The same product can be scanned as UPC-A (12 digits) or EAN-13 (the same digits with a leading 0).
    static func variants(_ code: String) -> [String] {
        var all = [code]
        if code.count == 12 { all.append("0" + code) }
        if code.count == 13, code.hasPrefix("0") { all.append(String(code.dropFirst())) }
        return all
    }
}

// MARK: - Rate limiter

/// Sliding-window limiter. `acquire` returns when a request may go out, waiting if that is soon,
/// and throws `.rateLimited` if the wait would be longer than `maxWait` (the UI should not hang).
actor OpenFoodFactsRateLimiter {
    private let maxRequests: Int
    private let window: TimeInterval
    private let maxWait: TimeInterval
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (TimeInterval) async throws -> Void
    private var sent: [Date] = []
    private var blockedUntil: Date?

    init(maxRequests: Int, per window: TimeInterval, maxWait: TimeInterval = 3,
         now: @escaping @Sendable () -> Date = { Date() },
         sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) }) {
        self.maxRequests = maxRequests; self.window = window; self.maxWait = maxWait
        self.now = now; self.sleep = sleep
    }

    /// Server said slow down (HTTP 429): refuse locally until then.
    func block(for seconds: TimeInterval) {
        blockedUntil = now().addingTimeInterval(max(1, min(seconds, 300)))
    }

    func acquire() async throws {
        let current = now()
        if let until = blockedUntil {
            if until > current { throw OpenFoodFactsError.rateLimited }
            blockedUntil = nil
        }
        sent.removeAll { current.timeIntervalSince($0) >= window }
        if sent.count >= maxRequests, let oldest = sent.first {
            let wait = window - current.timeIntervalSince(oldest)
            if wait > maxWait { throw OpenFoodFactsError.rateLimited }
            try await sleep(max(0, wait))
        }
        sent.append(now())
        // Keep the list bounded.
        if sent.count > maxRequests * 2 { sent.removeFirst(sent.count - maxRequests * 2) }
    }
}

// MARK: - Cache

/// Barcode results (30 days) and recent searches (10 minutes), in memory and mirrored to one JSON file.
final class OpenFoodFactsCache: @unchecked Sendable {
    static let barcodeTTL: TimeInterval = 30 * 86_400
    static let searchTTL: TimeInterval = 10 * 60
    private static let maxProducts = 300
    private static let maxSearches = 30

    private struct Stored: Codable {
        var products: [String: Timed<OpenFoodFactsProduct>] = [:]
        var searches: [String: Timed<[OpenFoodFactsProduct]>] = [:]
    }
    private struct Timed<Value: Codable>: Codable {
        var value: Value
        var storedAt: Date
    }

    private let lock = NSLock()
    private let fileURL: URL?
    private let now: () -> Date
    private var stored: Stored

    /// `fileURL` nil = memory only.
    init(fileURL: URL?, now: @escaping () -> Date = { Date() }) {
        self.fileURL = fileURL
        self.now = now
        if let fileURL, let data = try? Data(contentsOf: fileURL), let loaded = try? JSONDecoder().decode(Stored.self, from: data) {
            stored = loaded
        } else {
            stored = Stored()
        }
    }

    static func defaultFileURL() -> URL? {
        guard let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("OpenFoodFacts", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("cache.json")
    }

    private static func searchKey(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    func product(barcode: String) -> OpenFoodFactsProduct? {
        lock.lock(); defer { lock.unlock() }
        guard let item = stored.products[barcode] else { return nil }
        if now().timeIntervalSince(item.storedAt) > Self.barcodeTTL { stored.products[barcode] = nil; return nil }
        return item.value
    }

    func store(_ product: OpenFoodFactsProduct) {
        lock.lock(); defer { lock.unlock() }
        stored.products[product.barcode] = Timed(value: product, storedAt: now())
        prune()
        persist()
    }

    func search(_ query: String) -> [OpenFoodFactsProduct]? {
        lock.lock(); defer { lock.unlock() }
        let key = Self.searchKey(query)
        guard let item = stored.searches[key] else { return nil }
        if now().timeIntervalSince(item.storedAt) > Self.searchTTL { stored.searches[key] = nil; return nil }
        return item.value
    }

    func store(search query: String, results: [OpenFoodFactsProduct]) {
        lock.lock(); defer { lock.unlock() }
        let stamp = now()
        stored.searches[Self.searchKey(query)] = Timed(value: results, storedAt: stamp)
        // Search results also warm the barcode cache (same data), so opening one later needs no request.
        for product in results { stored.products[product.barcode] = Timed(value: product, storedAt: stamp) }
        prune()
        persist()
    }

    func clear() {
        lock.lock(); defer { lock.unlock() }
        stored = Stored()
        persist()
    }

    private func prune() {
        let stamp = now()
        stored.searches = stored.searches.filter { stamp.timeIntervalSince($0.value.storedAt) <= Self.searchTTL }
        if stored.searches.count > Self.maxSearches {
            let keep = stored.searches.sorted { $0.value.storedAt > $1.value.storedAt }.prefix(Self.maxSearches)
            stored.searches = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        }
        stored.products = stored.products.filter { stamp.timeIntervalSince($0.value.storedAt) <= Self.barcodeTTL }
        if stored.products.count > Self.maxProducts {
            let keep = stored.products.sorted { $0.value.storedAt > $1.value.storedAt }.prefix(Self.maxProducts)
            stored.products = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        }
    }

    private func persist() {
        guard let fileURL, let data = try? JSONEncoder().encode(stored) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

// MARK: - Live service

/// Talks to https://world.openfoodfacts.org.
///
/// Endpoint choices:
///  - Barcode: `GET /api/v2/product/{barcode}.json?fields=...` (documented, stable, ~100 req/min).
///  - Search: classic `GET /cgi/search.pl?search_terms=...&search_simple=1&action=process&json=1` (~10 req/min).
///    The newer search-a-licious service is faster but still beta with a different response shape, so the
///    documented v1 endpoint is used; swapping it later only touches `searchRequest` and the parser.
/// Requests carry a descriptive User-Agent (required by OFF) and no account or personal data.
final class OpenFoodFactsService: OpenFoodFactsServicing, @unchecked Sendable {

    typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    static let host = "world.openfoodfacts.org"

    private let transport: Transport
    private let cache: OpenFoodFactsCache
    private let userAgent: String
    private let productLimiter: OpenFoodFactsRateLimiter
    private let searchLimiter: OpenFoodFactsRateLimiter

    private let lock = NSLock()
    private var inFlightSearches: [String: Task<[OpenFoodFactsProduct], Error>] = [:]
    private var inFlightProducts: [String: Task<OpenFoodFactsProduct, Error>] = [:]

    init(transport: @escaping Transport = OpenFoodFactsService.urlSessionTransport(),
         cache: OpenFoodFactsCache = OpenFoodFactsCache(fileURL: OpenFoodFactsCache.defaultFileURL()),
         userAgent: String = OpenFoodFactsService.defaultUserAgent(),
         productLimiter: OpenFoodFactsRateLimiter = OpenFoodFactsRateLimiter(maxRequests: 80, per: 60),
         searchLimiter: OpenFoodFactsRateLimiter = OpenFoodFactsRateLimiter(maxRequests: 8, per: 60)) {
        self.transport = transport
        self.cache = cache
        self.userAgent = userAgent
        self.productLimiter = productLimiter
        self.searchLimiter = searchLimiter
    }

    static func defaultUserAgent(bundle: Bundle = .main) -> String {
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return "LightStack/\(version)\(build.map { " (\($0))" } ?? "") (iOS; nutrition)"
    }

    static func urlSessionTransport(session: URLSession = OpenFoodFactsService.makeSession()) -> Transport {
        { request in
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw OpenFoodFactsError.badData }
            return (data, http)
        }
    }

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 20
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }

    // MARK: Requests

    func productRequest(barcode: String) -> URLRequest? {
        var c = URLComponents()
        c.scheme = "https"; c.host = Self.host; c.path = "/api/v2/product/\(barcode).json"
        c.queryItems = [URLQueryItem(name: "fields", value: OpenFoodFactsParser.fields)]
        return c.url.map(request(for:))
    }

    func searchRequest(query: String) -> URLRequest? {
        var c = URLComponents()
        c.scheme = "https"; c.host = Self.host; c.path = "/cgi/search.pl"
        c.queryItems = [
            URLQueryItem(name: "search_terms", value: query),
            URLQueryItem(name: "search_simple", value: "1"),
            URLQueryItem(name: "action", value: "process"),
            URLQueryItem(name: "json", value: "1"),
            URLQueryItem(name: "page_size", value: "20"),
            URLQueryItem(name: "sort_by", value: "unique_scans_n"),
            URLQueryItem(name: "fields", value: OpenFoodFactsParser.fields)
        ]
        return c.url.map(request(for:))
    }

    private func request(for url: URL) -> URLRequest {
        var r = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        r.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        return r
    }

    // MARK: API

    func product(barcode raw: String) async throws -> OpenFoodFactsProduct {
        guard let code = Barcode.normalized(raw) else { throw OpenFoodFactsError.notFound }
        if let cached = cache.product(barcode: code) { return cached }

        let task: Task<OpenFoodFactsProduct, Error> = lock.withLock {
            if let existing = inFlightProducts[code] { return existing }
            let new = Task { [self] in
                defer { lock.withLock { inFlightProducts[code] = nil } }
                guard let request = productRequest(barcode: code) else { throw OpenFoodFactsError.badData }
                let data = try await perform(request, limiter: productLimiter)
                let product = try OpenFoodFactsParser.parseProductResponse(data)
                cache.store(product)
                return product
            }
            inFlightProducts[code] = new
            return new
        }
        return try await task.value
    }

    func search(query raw: String) async throws -> [OpenFoodFactsProduct] {
        let query = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else { return [] }
        let capped = String(query.prefix(100))
        if let cached = cache.search(capped) { return cached }

        let key = capped.lowercased()
        let task: Task<[OpenFoodFactsProduct], Error> = lock.withLock {
            if let existing = inFlightSearches[key] { return existing }
            let new = Task { [self] in
                defer { lock.withLock { inFlightSearches[key] = nil } }
                guard let request = searchRequest(query: capped) else { throw OpenFoodFactsError.badData }
                let data = try await perform(request, limiter: searchLimiter)
                let products = try OpenFoodFactsParser.parseSearchResponse(data)
                cache.store(search: capped, results: products)
                return products
            }
            inFlightSearches[key] = new
            return new
        }
        return try await task.value
    }

    // MARK: Transport

    private func perform(_ request: URLRequest, limiter: OpenFoodFactsRateLimiter) async throws -> Data {
        try await limiter.acquire()
        do {
            let (data, http) = try await transport(request)
            switch http.statusCode {
            case 200...299: return data
            case 404:
                // v2 answers an unknown barcode with 404 and a JSON body; a search never 404s.
                throw OpenFoodFactsError.notFound
            case 429:
                let retry = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init) ?? 60
                await limiter.block(for: retry)
                throw OpenFoodFactsError.rateLimited
            default:
                throw OpenFoodFactsError.unavailable
            }
        } catch let error as OpenFoodFactsError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw OpenFoodFactsError.offline
        } catch {
            throw OpenFoodFactsError.unavailable
        }
    }
}
