import XCTest
import SceneKit
import UIKit
@testable import Lightstack

/// Visual QA tool: renders one labelled contact sheet per guide exercise into /tmp/guide-sheets.
/// Runs only when the GUIDE_SHEETS environment variable is set (pass TEST_RUNNER_GUIDE_SHEETS=1 to xcodebuild).
/// GUIDE_SHEETS_FILTER limits it to exercises whose id or name contains the text; GUIDE_SHEETS_DARK=0 renders light.
final class GuideContactSheetTests: XCTestCase {

    private var tile: CGFloat = 540
    private let headerHeight: CGFloat = 64

    func testRenderContactSheets() throws {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipIf(env["GUIDE_SHEETS"] == nil, "Set TEST_RUNNER_GUIDE_SHEETS=1 to render the guide contact sheets")
        let filter = env["GUIDE_SHEETS_FILTER"]?.lowercased()
        let dark = env["GUIDE_SHEETS_DARK"] != "0"
        if let t = env["GUIDE_SHEETS_TILE"].flatMap({ Double($0) }) { tile = CGFloat(t) }

        let dir = URL(fileURLWithPath: env["GUIDE_SHEETS_DIR"] ?? "/tmp/guide-sheets", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice(), "No Metal device")
        let controller = GuideSceneController(appearance: GuideSceneAppearance(isDark: dark), startsPlaying: false)
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = controller.scene
        renderer.pointOfView = controller.cameraNode
        renderer.autoenablesDefaultLighting = false
        controller.updateAspect(CameraFraming.stageAspect)

        let angles = ExerciseMotionLibrary.all.map { GuideMotionDebug.describe($0) }.joined(separator: "\n")
        try angles.write(to: dir.appendingPathComponent("angles.txt"), atomically: true, encoding: .utf8)
        var index: [String] = []
        let all = ExerciseMotionLibrary.all
        for (n, motion) in all.enumerated() {
            let fileName = String(format: "%02d-%@.png", n + 1, motion.id)
            index.append("\(fileName) -> \(motion.exerciseName)")
            if let filter, !motion.id.lowercased().contains(filter), !motion.exerciseName.lowercased().contains(filter) { continue }
            try autoreleasepool {
                controller.load(motion: motion, animatedHighlight: false)
                let tiles: [(GuideCameraPreset, Float, String)] = [
                    (.side, 0, "SIDE  0.00"), (.side, 0.5, "SIDE  0.50"),
                    (.front, 0.5, "FRONT  0.50"), (.back, 0.5, "BACK  0.50"), (.threeQuarter, 0, "3/4  0.00"), (.threeQuarter, 0.5, "3/4  0.50")
                ]
                let tileH = (tile / CGFloat(CameraFraming.stageAspect)).rounded()
                let size = CGSize(width: tile * 2, height: headerHeight + tileH * 3)
                let format = UIGraphicsImageRendererFormat()
                format.scale = 1
                let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
                    UIColor(white: 0.07, alpha: 1).setFill()
                    ctx.fill(CGRect(origin: .zero, size: size))
                    let title = "\(n + 1). \(motion.exerciseName)  [\(motion.id)]" as NSString
                    title.draw(at: CGPoint(x: 12, y: 8), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 20), .foregroundColor: UIColor.white])
                    let muscles = "PRIMARY: \(motion.primaryMuscles.map(\.rawValue).joined(separator: ", "))   SECONDARY: \(motion.secondaryMuscles.map(\.rawValue).joined(separator: ", "))   cam: \(motion.defaultCamera.rawValue)" as NSString
                    muscles.draw(at: CGPoint(x: 12, y: 36), withAttributes: [.font: UIFont.systemFont(ofSize: 14), .foregroundColor: UIColor(white: 0.8, alpha: 1)])
                    for (i, t) in tiles.enumerated() {
                        controller.setProgress(t.1)
                        controller.setCamera(t.0, animated: false)
                        let snap = renderer.snapshot(atTime: 0, with: CGSize(width: tile, height: tileH), antialiasingMode: .multisampling4X)
                        let origin = CGPoint(x: CGFloat(i % 2) * tile, y: headerHeight + CGFloat(i / 2) * tileH)
                        snap.draw(in: CGRect(origin: origin, size: CGSize(width: tile, height: tileH)))
                        (t.2 as NSString).draw(at: CGPoint(x: origin.x + 8, y: origin.y + 6),
                                               withAttributes: [.font: UIFont.boldSystemFont(ofSize: 14), .foregroundColor: UIColor(white: 0.7, alpha: 1)])
                    }
                }
                try XCTUnwrap(image.pngData()).write(to: dir.appendingPathComponent(fileName))
            }
        }
        try (index.joined(separator: "\n") + "\n").write(to: dir.appendingPathComponent("index.txt"), atomically: true, encoding: .utf8)
    }
}
