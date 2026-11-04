import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Estimates a meal from a description and/or a photo.
protocol NutritionAIServicing: Sendable {
    /// One call = one AI request (plus the existing model fallback). Throws `NutritionAIError`.
    func estimate(text: String, image: Data?, mealContext: AIMealContext?) async throws -> AIMealEstimate
}

/// The real thing: reaches Gemini through the shared `AIServiceManager` (gemini-3.5-flash, then 2.5-flash),
/// i.e. the ai-proxy Edge Function with its per-user rate limit.
final class NutritionAIService: NutritionAIServicing, @unchecked Sendable {

    private let manager: AIServiceManager

    init(manager: AIServiceManager) { self.manager = manager }

    func estimate(text: String, image: Data?, mealContext: AIMealContext?) async throws -> AIMealEstimate {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || image != nil else { throw NutritionAIError.empty }

        let jpeg = try image.map { try NutritionPhotoPreparer.prepare($0) }
        let request = NutritionAIPrompt.build(text: trimmed, imageJPEG: jpeg, context: mealContext)

        let reply: AIReply = try await withCheckedThrowingContinuation { continuation in
            manager.generateReply(
                systemPrompt: request.systemPrompt,
                messages: request.messages,
                expectsJSON: true,
                options: request.options
            ) { result in
                continuation.resume(with: result.mapError { NutritionAIError.from($0) })
            }
        }
        try Task.checkCancellation()
        return try NutritionAIParser.estimate(from: reply, usedSearch: request.options.googleSearch)
    }
}

// MARK: - Photo preparation

/// Shrinks a meal photo so it fits the proxy: long edge at most 1024 px, JPEG quality about 0.6, and the
/// base64 text kept under the proxy's 3,000,000 character body limit (with room for the prompt).
enum NutritionPhotoPreparer {
    static let maxLongEdge = 1024
    static let maxBase64Chars = 2_500_000

    static func prepare(_ data: Data) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { throw NutritionAIError.failed("That photo couldn't be read.") }
        var edge = maxLongEdge
        var quality = 0.6
        for _ in 0..<6 {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: edge
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                throw NutritionAIError.failed("That photo couldn't be read.")
            }
            let output = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
                throw NutritionAIError.failed("That photo couldn't be processed.")
            }
            CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { throw NutritionAIError.failed("That photo couldn't be processed.") }
            let jpeg = output as Data
            // base64 grows by 4/3.
            if jpeg.count * 4 / 3 + 4 <= maxBase64Chars { return jpeg }
            edge = Int(Double(edge) * 0.75)
            quality = max(0.3, quality - 0.1)
        }
        throw NutritionAIError.failed("That photo is too large to send. Try another one.")
    }
}
