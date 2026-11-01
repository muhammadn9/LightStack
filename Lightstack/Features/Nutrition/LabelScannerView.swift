import SwiftUI
import AVFoundation
import VisionKit

/// Scan sheet: live camera text capture, then the review form. Camera only (no photo-library import).
struct ScanFlowView: View {
    @ObservedObject var viewModel: NutritionViewModel
    var mealSlotId: UUID?
    var onLogged: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var parsed: ParsedLabel?

    var body: some View {
        NavigationStack {
            LabelScannerView(
                onUse: { lines in parsed = NutritionLabelParser.parse(lines: lines) },
                onManual: { parsed = NutritionLabelParser.parse(text: "") }
            )
            .navigationTitle("Scan label")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .navigationDestination(isPresented: Binding(get: { parsed != nil }, set: { if !$0 { parsed = nil } })) {
                if let parsed {
                    FoodReviewView(viewModel: viewModel, mealSlotId: mealSlotId, parsed: parsed) {
                        onLogged?()
                        dismiss()
                    }
                }
            }
        }
        .keyboardDoneButton()
    }
}

/// Chooses the real scanner, the unsupported-device fallback, or (UI tests only) the stub.
struct LabelScannerView: View {
    let onUse: ([OCRLine]) -> Void
    let onManual: () -> Void

    @State private var access: ScannerAccess = .checking

    enum ScannerAccess { case checking, ready, unsupported, denied }

    var body: some View {
        #if DEBUG
        if UITestMode.isActive {
            ScanStubView(onUse: onUse)
        } else {
            realBody
        }
        #else
        realBody
        #endif
    }

    @ViewBuilder
    private var realBody: some View {
        switch access {
        case .checking:
            AppTheme.background.ignoresSafeArea()
                .overlay { ProgressView() }
                .task { await checkAccess() }
        case .ready:
            LiveScannerContainer(onUse: onUse)
        case .unsupported:
            fallback("Scanning isn't available on this device.",
                     detail: "You can still enter the values from the label by hand.")
        case .denied:
            fallback("Camera access is off.",
                     detail: "Turn it on in Settings to scan labels, or enter the values by hand.")
        }
    }

    private func fallback(_ title: String, detail: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "camera.metering.unknown")
                .font(.largeTitle)
                .foregroundStyle(AppTheme.textSecondary)
                .accessibilityHidden(true)
            Text(title).font(.headline).foregroundStyle(AppTheme.textPrimary)
            Text(detail).font(.subheadline).foregroundStyle(AppTheme.textSecondary).multilineTextAlignment(.center)
            Button(action: onManual) {
                Text("Enter values by hand")
                    .font(.headline)
                    .foregroundStyle(AppTheme.onAccent)
                    .frame(maxWidth: .infinity, minHeight: AppTheme.minTouchSize)
                    .background(AppTheme.accent, in: Capsule())
            }
            .accessibilityIdentifier("nutrition.scan.manual")
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.background.ignoresSafeArea())
    }

    private func checkAccess() async {
        guard DataScannerViewController.isSupported else { access = .unsupported; return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            access = DataScannerViewController.isAvailable ? .ready : .unsupported
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            access = granted ? (DataScannerViewController.isAvailable ? .ready : .unsupported) : .denied
        default:
            access = .denied
        }
    }
}

// MARK: - Live scanner

private struct LiveScannerContainer: View {
    let onUse: ([OCRLine]) -> Void
    @StateObject private var collector = ScanCollector()

    var body: some View {
        ZStack(alignment: .bottom) {
            DataScannerRepresentable(collector: collector)
                .ignoresSafeArea()
            VStack(spacing: 10) {
                Text(collector.count == 0 ? "Point the camera at the Nutrition Facts label"
                     : "\(collector.count) lines read. Hold steady, then tap Use this.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(10)
                    .background(AppTheme.surface.opacity(0.92), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Button { onUse(collector.lines()) } label: {
                    Text("Use this")
                        .font(.headline)
                        .foregroundStyle(AppTheme.onAccent)
                        .frame(maxWidth: .infinity, minHeight: AppTheme.minTouchSize)
                        .background(AppTheme.accent, in: Capsule())
                }
                .disabled(collector.count == 0)
                .opacity(collector.count == 0 ? 0.5 : 1)
                .accessibilityIdentifier("nutrition.scan.use")
            }
            .padding(16)
        }
    }
}

/// Accumulates recognised lines across frames (keyed by item id, so a line is updated, not duplicated).
@MainActor
final class ScanCollector: ObservableObject {
    @Published private(set) var count = 0
    private var items: [UUID: OCRLine] = [:]
    private var order: [UUID] = []
    var viewSize: CGSize = .zero

    func upsert(_ item: RecognizedItem) {
        guard case .text(let text) = item else { return }
        let size = viewSize
        var box = CGRect.zero
        if size.width > 0, size.height > 0 {
            let b = text.bounds
            let xs = [b.topLeft.x, b.topRight.x, b.bottomLeft.x, b.bottomRight.x]
            let ys = [b.topLeft.y, b.topRight.y, b.bottomLeft.y, b.bottomRight.y]
            if let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() {
                box = CGRect(x: minX / size.width, y: minY / size.height,
                             width: (maxX - minX) / size.width, height: (maxY - minY) / size.height)
            }
        }
        if items[item.id] == nil { order.append(item.id) }
        items[item.id] = OCRLine(text: text.transcript, box: box)
        count = items.count
    }

    func lines() -> [OCRLine] {
        order.compactMap { items[$0] }
    }
}

private struct DataScannerRepresentable: UIViewControllerRepresentable {
    let collector: ScanCollector

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.text()],
            qualityLevel: .accurate,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        collector.viewSize = scanner.view.bounds.size
        if !scanner.isScanning {
            try? scanner.startScanning()
        }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(collector: collector) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let collector: ScanCollector
        init(collector: ScanCollector) { self.collector = collector }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            collector.viewSize = dataScanner.view.bounds.size
            addedItems.forEach { collector.upsert($0) }
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didUpdate updatedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            collector.viewSize = dataScanner.view.bounds.size
            updatedItems.forEach { collector.upsert($0) }
        }
    }
}
