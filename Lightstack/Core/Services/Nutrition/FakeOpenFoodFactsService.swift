#if DEBUG
import Foundation

/// Deterministic stand-in for Open Food Facts: used under `-uiTesting` (the real network is never touched)
/// and by unit tests. Search matches by substring on name and brand; barcodes come from `products`.
final class FakeOpenFoodFactsService: OpenFoodFactsServicing, @unchecked Sendable {

    private let lock = NSLock()
    private var _products: [OpenFoodFactsProduct]
    private var _searchCalls: [String] = []
    private var _barcodeCalls: [String] = []
    private var _error: OpenFoodFactsError?
    private var _delay: TimeInterval

    init(products: [OpenFoodFactsProduct] = FakeOpenFoodFactsService.catalog, error: OpenFoodFactsError? = nil, delay: TimeInterval = 0) {
        _products = products; _error = error; _delay = delay
    }

    var searchCalls: [String] { lock.withLock { _searchCalls } }
    var barcodeCalls: [String] { lock.withLock { _barcodeCalls } }
    var error: OpenFoodFactsError? {
        get { lock.withLock { _error } }
        set { lock.withLock { _error = newValue } }
    }
    var delay: TimeInterval {
        get { lock.withLock { _delay } }
        set { lock.withLock { _delay = newValue } }
    }

    func product(barcode raw: String) async throws -> OpenFoodFactsProduct {
        lock.withLock { _barcodeCalls.append(raw) }
        try await wait()
        guard let code = Barcode.normalized(raw) else { throw OpenFoodFactsError.notFound }
        let (products, error) = lock.withLock { (_products, _error) }
        if let error { throw error }
        guard let match = products.first(where: { Barcode.variants(code).contains($0.barcode) }) else {
            throw OpenFoodFactsError.notFound
        }
        return match
    }

    func search(query raw: String) async throws -> [OpenFoodFactsProduct] {
        lock.withLock { _searchCalls.append(raw) }
        try await wait()
        let query = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard query.count >= 2 else { return [] }
        let (products, error) = lock.withLock { (_products, _error) }
        if let error { throw error }
        return products.filter { $0.name.lowercased().contains(query) || ($0.brand?.lowercased().contains(query) ?? false) }
    }

    private func wait() async throws {
        let seconds = delay
        if seconds > 0 { try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
        try Task.checkCancellation()
    }

    // MARK: Fixtures

    /// Barcode 0123456789012 is found (Fage Total 0% Greek Yogurt); 0000000000000 is not in the catalog.
    static let catalog: [OpenFoodFactsProduct] = [
        OpenFoodFactsProduct(
            barcode: "0123456789012", name: "Total 0% Greek Yogurt", brand: "Fage", servingLabel: "170 g",
            servingUnit: "g", servingAmount: 170, hasServingSize: true,
            nutrients: NutrientValues(kcal: 90, protein: 18, carbs: 5, fat: 0,
                                      micros: Micronutrients(values: [.sugar: 5, .sodium: 65]))),
        OpenFoodFactsProduct(
            barcode: "5000000000011", name: "Greek Yogurt Strawberry", brand: "Chobani", servingLabel: "150 g",
            servingUnit: "g", servingAmount: 150, hasServingSize: true,
            nutrients: NutrientValues(kcal: 120, protein: 12, carbs: 14, fat: 2.5, micros: Micronutrients(values: [.sugar: 12]))),
        OpenFoodFactsProduct(
            barcode: "7622300000017", name: "Oreo Original Cookies", brand: "Oreo", servingLabel: "34 g",
            servingUnit: "g", servingAmount: 34, hasServingSize: true,
            nutrients: NutrientValues(kcal: 160, protein: 1, carbs: 25, fat: 7, micros: Micronutrients(values: [.sugar: 14, .satFat: 2]))),
        OpenFoodFactsProduct(
            barcode: "7622300000024", name: "Oreo Thins", brand: "Oreo", servingLabel: "100 g",
            servingUnit: "g", servingAmount: 100, hasServingSize: false,
            nutrients: NutrientValues(kcal: 480, protein: 5, carbs: 70, fat: 20), warnings: [.per100Only])
    ]

    static func uiTesting() -> FakeOpenFoodFactsService { FakeOpenFoodFactsService() }
}
#endif
