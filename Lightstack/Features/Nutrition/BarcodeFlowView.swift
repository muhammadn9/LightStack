import SwiftUI
import AVFoundation
import VisionKit

/// Barcode sheet: scan (or type) a code, look it up, then log it, or offer label scan / manual entry when unknown.
struct BarcodeFlowView: View {
    @ObservedObject var viewModel: NutritionViewModel
    var mealSlotId: UUID?
    /// When set, the serving screen also offers "Add to plate".
    var onPlate: ((NutritionFood, Double) -> Void)?
    var onLogged: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    private enum Candidate {
        case local(NutritionFood)
        case remote(OpenFoodFactsProduct)
    }

    private enum Stage {
        case scan, lookingUp(String), serving(Candidate), notFound(String), failed(String, String)
    }

    private enum Inner: Identifiable {
        case label(String), create(String)
        var id: String { switch self { case .label: return "label"; case .create: return "create" } }
    }

    @State private var stage: Stage = .scan
    @State private var inner: Inner?

    private var mealName: String { viewModel.slot(id: mealSlotId)?.name ?? "Meal" }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Scan barcode")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .keyboardDoneButton()
        .sheet(item: $inner) { item in
            switch item {
            case .label(let code):
                ScanFlowView(viewModel: viewModel, mealSlotId: mealSlotId, barcode: code, onLogged: finishLogged)
            case .create(let code):
                CreateFoodView(viewModel: viewModel, mealSlotId: mealSlotId, logByDefault: true, barcode: code,
                               onLogged: finishLogged)
            }
        }
    }

    private func finishLogged() {
        onLogged?()
        dismiss()
    }

    @ViewBuilder private var content: some View {
        switch stage {
        case .scan:
            BarcodeScannerView(onCode: lookUp)
        case .lookingUp(let code):
            VStack(spacing: 14) {
                ProgressView()
                Text("Looking up \(code)…").font(.subheadline).foregroundStyle(AppTheme.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppTheme.background.ignoresSafeArea())
            .accessibilityIdentifier("barcode.loading")
        case .serving(let candidate):
            serving(candidate)
        case .notFound(let code):
            message(icon: "magnifyingglass", title: "Not found",
                    detail: "No food with barcode \(code) yet. Scan its nutrition label or create it by hand, and the next scan will find it.",
                    id: "barcode.notfound") {
                actionButton("Scan nutrition label", id: "barcode.scanLabel", filled: true) { inner = .label(code) }
                actionButton("Create food", id: "barcode.create", filled: false) { inner = .create(code) }
                actionButton("Scan another", id: "barcode.again", filled: false) { stage = .scan }
            }
        case .failed(let text, let code):
            message(icon: "wifi.exclamationmark", title: "Couldn't look that up", detail: text, id: "barcode.failed") {
                actionButton("Retry", id: "barcode.retry", filled: true) { lookUp(code) }
                actionButton("Create food", id: "barcode.create", filled: false) { inner = .create(code) }
            }
        }
    }

    @ViewBuilder private func serving(_ candidate: Candidate) -> some View {
        switch candidate {
        case .local(let food):
            BrandedServingView(
                target: ServingTarget(food: food), mealName: mealName,
                onAdd: { servings in
                    viewModel.logPlate([PlateItem(food: food, servings: servings)], mealSlotId: mealSlotId)
                    finishLogged()
                },
                onPlate: onPlate.map { plate in { servings in plate(food, servings); dismiss() } }
            )
        case .remote(let product):
            BrandedServingView(
                target: ServingTarget(product: product), mealName: mealName,
                onAdd: { servings in
                    viewModel.saveBrandedFood(product, logServings: servings, mealSlotId: mealSlotId)
                    finishLogged()
                },
                onPlate: onPlate.map { plate in { servings in
                    if let food = viewModel.saveBrandedFood(product) { plate(food, servings) }
                    dismiss()
                } }
            )
        }
    }

    private func lookUp(_ code: String) {
        stage = .lookingUp(code)
        Task { @MainActor in
            switch await viewModel.lookupBarcode(code) {
            case .local(let food): stage = .serving(.local(food))
            case .remote(let product): stage = .serving(.remote(product))
            case .notFound: stage = .notFound(code)
            case .failed(let text): stage = .failed(text, code)
            }
        }
    }

    private func message<Actions: View>(icon: String, title: String, detail: String, id: String,
                                        @ViewBuilder actions: () -> Actions) -> some View {
        VStack(spacing: 14) {
            Image(systemName: icon).font(.largeTitle).foregroundStyle(AppTheme.textSecondary).accessibilityHidden(true)
            Text(title).font(.title3.weight(.semibold)).foregroundStyle(AppTheme.textPrimary)
                .accessibilityIdentifier(id)
            Text(detail).font(.subheadline).foregroundStyle(AppTheme.textSecondary).multilineTextAlignment(.center)
            actions()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.background.ignoresSafeArea())
    }

    private func actionButton(_ title: String, id: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.headline)
                .foregroundStyle(filled ? AppTheme.onAccent : AppTheme.accent)
                .frame(maxWidth: .infinity, minHeight: AppTheme.minTouchSize)
                .background(filled ? AppTheme.accent : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}

// MARK: - Scanner chooser

/// Live scanner, or typed entry when the camera is unavailable (and always in UI tests).
struct BarcodeScannerView: View {
    let onCode: (String) -> Void

    private enum Access { case checking, ready, unsupported, denied }
    @State private var access: Access = .checking
    @State private var typing = false

    var body: some View {
        #if DEBUG
        if UITestMode.isActive {
            BarcodeManualEntry(headline: "Scanner stub", detail: "Type a barcode to look up.", onSubmit: onCode)
        } else {
            real
        }
        #else
        real
        #endif
    }

    @ViewBuilder private var real: some View {
        switch access {
        case .checking:
            AppTheme.background.ignoresSafeArea().overlay { ProgressView() }
                .task { await check() }
        case .ready:
            if typing {
                BarcodeManualEntry(headline: "Enter barcode", detail: "Type the digits under the barcode.", onSubmit: onCode)
            } else {
                ZStack(alignment: .bottom) {
                    BarcodeScannerRepresentable(onCode: onCode).ignoresSafeArea()
                    VStack(spacing: 10) {
                        Text("Point the camera at a barcode")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.textPrimary)
                            .padding(10)
                            .background(AppTheme.surface.opacity(0.92), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        Button { typing = true } label: {
                            Text("Type barcode instead").font(.headline).foregroundStyle(AppTheme.textPrimary)
                                .frame(maxWidth: .infinity, minHeight: AppTheme.minTouchSize)
                                .background(AppTheme.surface.opacity(0.92), in: Capsule())
                        }
                        .accessibilityIdentifier("barcode.type")
                    }
                    .padding(16)
                }
            }
        case .unsupported:
            BarcodeManualEntry(headline: "Scanning isn't available on this device",
                               detail: "Type the barcode digits instead.", onSubmit: onCode)
        case .denied:
            BarcodeManualEntry(headline: "Camera access is off",
                               detail: "Turn it on in Settings to scan, or type the barcode digits instead.",
                               showSettings: true, onSubmit: onCode)
        }
    }

    private func check() async {
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

/// Type a barcode: the fallback when the camera cannot scan, and the stand-in used by UI tests.
struct BarcodeManualEntry: View {
    let headline: String
    let detail: String
    var showSettings = false
    let onSubmit: (String) -> Void

    @State private var text = ""
    private var code: String? { Barcode.normalized(text) }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Image(systemName: "barcode.viewfinder").font(.largeTitle).foregroundStyle(AppTheme.accent)
                    .accessibilityHidden(true)
                Text(headline).font(.headline).foregroundStyle(AppTheme.textPrimary)
                    .accessibilityIdentifier("barcode.stub")
                Text(detail).font(.subheadline).foregroundStyle(AppTheme.textSecondary).multilineTextAlignment(.center)
                TextField("Barcode (8 to 14 digits)", text: $text)
                    .keyboardType(.numberPad)
                    .padding(.horizontal, 14).frame(minHeight: 48)
                    .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityIdentifier("nutrition.barcode.field")
                Button { if let code { onSubmit(code) } } label: {
                    Text("Look up").font(.headline).foregroundStyle(AppTheme.onAccent)
                        .frame(maxWidth: .infinity, minHeight: AppTheme.minTouchSize)
                        .background(code == nil ? AppTheme.textSecondary.opacity(0.4) : AppTheme.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(code == nil)
                .accessibilityIdentifier("nutrition.barcode.lookup")
                if showSettings, let url = URL(string: UIApplication.openSettingsURLString) {
                    Link("Open Settings", destination: url).frame(minHeight: 44)
                        .accessibilityIdentifier("barcode.settings")
                }
            }
            .padding(24)
        }
        .background(AppTheme.background.ignoresSafeArea())
    }
}

// MARK: - Live scanner

private struct BarcodeScannerRepresentable: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        if !scanner.isScanning { try? scanner.startScanning() }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        private var handled = false
        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !handled else { return }
            for item in addedItems {
                guard case .barcode(let barcode) = item, let value = barcode.payloadStringValue,
                      let code = Barcode.normalized(value) else { continue }
                handled = true
                dataScanner.stopScanning()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                onCode(code)
                return
            }
        }
    }
}
