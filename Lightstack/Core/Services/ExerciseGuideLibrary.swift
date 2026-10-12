import Foundation
import UIKit
import os

/// Photos and step-by-step instructions for an exercise, bundled offline.
/// Source: free-exercise-db (public domain, Unlicense).
struct ExerciseGuide: Equatable {
    let catalogName: String
    let sourceId: String
    let instructions: [String]
    /// File names inside the bundled `ExerciseGuides` folder: start photo first, end photo second.
    let imageFiles: [String]
}

final class ExerciseGuideLibrary {

    static let shared = ExerciseGuideLibrary()

    private static let logger = Logger(subsystem: "org.lightstack.app", category: "ExerciseGuideLibrary")
    private static let folder = "ExerciseGuides"

    private struct FileModel: Decodable {
        let credits: String?
        let guides: [Entry]
    }
    private struct Entry: Decodable {
        let catalogName: String
        let sourceId: String
        let instructions: [String]
        let images: [String]
    }

    private let guides: [ExerciseGuide]
    private let byLowercasedName: [String: ExerciseGuide]

    /// Loads from `bundle`'s `ExerciseGuides/exercise_guides.json`. Loading is cheap (one small JSON);
    /// images are only read when a view asks for them.
    init(bundle: Bundle = .main) {
        let url = bundle.url(forResource: "exercise_guides", withExtension: "json", subdirectory: Self.folder)
        var loaded: [ExerciseGuide] = []
        if let url {
            do {
                let model = try JSONDecoder().decode(FileModel.self, from: Data(contentsOf: url))
                loaded = model.guides.map {
                    ExerciseGuide(catalogName: $0.catalogName, sourceId: $0.sourceId,
                                  instructions: $0.instructions, imageFiles: $0.images)
                }
            } catch {
                Self.logger.error("Could not load exercise guides: \(error.localizedDescription, privacy: .public)")
            }
        } else {
            Self.logger.error("exercise_guides.json missing from bundle")
        }
        guides = loaded
        byLowercasedName = Dictionary(loaded.map { ($0.catalogName.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Catalog names that have a bundled guide.
    var mappedCatalogNames: [String] { guides.map(\.catalogName) }

    /// Exact (case-insensitive) catalog match first, then the closest catalog name by
    /// `ExerciseNameResolver`. nil when nothing is close enough.
    func guide(for exerciseName: String) -> ExerciseGuide? {
        let typed = exerciseName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else { return nil }
        if let exact = byLowercasedName[typed.lowercased()] { return exact }
        // Match against every catalog name (not just mapped ones) so a custom name that
        // resolves to an unmapped exercise does not get a different exercise's photos.
        let known = ExerciseCatalog.exercises.map(\.name)
        guard let best = ExerciseNameResolver.suggestions(for: typed, among: known).first else { return nil }
        return byLowercasedName[best.lowercased()]
    }

    static func image(named file: String, bundle: Bundle = .main) -> UIImage? {
        guard let path = bundle.path(forResource: file, ofType: nil, inDirectory: folder) else { return nil }
        return UIImage(contentsOfFile: path)
    }
}
