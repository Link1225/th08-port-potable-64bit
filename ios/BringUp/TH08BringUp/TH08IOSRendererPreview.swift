import SwiftUI

struct TH08IOSRendererPreview: UIViewRepresentable {
    func makeUIView(context: Context) -> TH08IOSRendererPreviewView {
        let view = TH08IOSRendererPreviewView(frame: .zero)
        view.setNeedsDisplay()
        return view
    }

    func updateUIView(_ uiView: TH08IOSRendererPreviewView, context: Context) {
        uiView.setNeedsDisplay()
    }
}
