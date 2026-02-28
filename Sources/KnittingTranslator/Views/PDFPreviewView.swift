import SwiftUI
import PDFKit

struct PDFPreviewView: NSViewRepresentable {
    let document: PDFDocument

    func makeNSView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.displayMode = .singlePageContinuous
        v.backgroundColor = .windowBackgroundColor
        return v
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        // URL equality check prevents re-loading on every SwiftUI re-render
        if nsView.document?.documentURL != document.documentURL {
            nsView.document = document
        }
    }
}
