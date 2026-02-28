import AppKit
import Foundation
import WebKit

enum PDFRendererError: LocalizedError {
    case printFailed
    var errorDescription: String? { "PDFの生成に失敗しました" }
}

/// WKWebView + NSPrintOperation を使って HTML を A4 PDF として保存する。
/// createPDF() はスクリーンキャプチャのため改ページされない。
/// printOperation(with:) を使うと CSS @page / @media print が正しく機能する。
@MainActor
final class WebViewPDFRenderer: NSObject, WKNavigationDelegate {

    private var webView: WKWebView?
    private var loadContinuation: CheckedContinuation<Void, Error>?

    /// HTML を A4 PDF として url に保存する（同期的にディスクへ書き出し）
    func renderPDF(from html: String, to url: URL) async throws {
        // A4 ポイントサイズに合わせたビューポートで WKWebView を作成
        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 595, height: 842))
        wv.navigationDelegate = self
        self.webView = wv

        // HTML ロード完了を待つ
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            self.loadContinuation = cont
            wv.loadHTMLString(html, baseURL: nil)
        }

        // レンダリングが安定するまで少し待つ
        try await Task.sleep(for: .milliseconds(300))

        // A4 用紙設定（1pt = 1/72inch）
        // 15mm ≈ 42.5pt, 12mm ≈ 34pt
        let printInfo = NSPrintInfo.shared.copy() as! NSPrintInfo
        printInfo.paperSize     = NSSize(width: 595.28, height: 841.89)
        printInfo.orientation   = .portrait
        printInfo.topMargin     = 42.5
        printInfo.bottomMargin  = 42.5
        printInfo.leftMargin    = 34.0
        printInfo.rightMargin   = 34.0
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination   = .automatic
        printInfo.isHorizontallyCentered = false
        printInfo.isVerticallyCentered   = false

        // ダイアログなしで URL に PDF 保存
        let dict = printInfo.dictionary()
        dict.setObject("NSPrintSaveJob",  forKey: "NSJobDisposition" as NSString)
        dict.setObject(url as NSURL,      forKey: "NSJobSavingURL"   as NSString)

        let printOp = wv.printOperation(with: printInfo)
        printOp.showsProgressPanel = false
        printOp.showsPrintPanel    = false

        guard printOp.run() else {
            throw PDFRendererError.printFailed
        }
    }

    // MARK: - WKNavigationDelegate

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor [weak self] in
            self?.loadContinuation?.resume()
            self?.loadContinuation = nil
        }
    }

    nonisolated func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        Task { @MainActor [weak self] in
            self?.loadContinuation?.resume(throwing: error)
            self?.loadContinuation = nil
        }
    }

    nonisolated func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        Task { @MainActor [weak self] in
            self?.loadContinuation?.resume(throwing: error)
            self?.loadContinuation = nil
        }
    }
}
