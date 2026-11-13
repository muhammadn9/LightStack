import SwiftUI
import AVFoundation

/// Live camera preview. The layer *is* the view's layer, so there is no frame syncing to get wrong.
struct CameraPreviewView: UIViewRepresentable {

    let session: AVCaptureSession
    let source: PoseSource

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.backgroundColor = .black
        if let layer = view.previewLayer {
            layer.session = session
            layer.videoGravity = .resizeAspectFill
            // The source keeps the layer's rotation angle in step with gravity.
            source.attachPreviewLayer(layer)
        }
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {}

    static func dismantleUIView(_ uiView: PreviewUIView, coordinator: ()) {
        uiView.previewLayer?.session = nil
    }
}

final class PreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer? { layer as? AVCaptureVideoPreviewLayer }
}
