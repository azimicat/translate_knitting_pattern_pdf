import AppKit
import CoreGraphics
import Foundation

struct HTMLGenerator {

    /// ページグルーピングして2カラムHTMLを生成する
    func generateHTML(pairs: [TranslationPair], images: [ExtractedImage]) -> String {
        let maxPage = max(
            pairs.map(\.pageIndex).max() ?? 0,
            images.map(\.pageIndex).max() ?? 0
        )

        // ページごとに仕分け
        var pairsByPage  = Array(repeating: [TranslationPair](),  count: maxPage + 1)
        var imagesByPage = Array(repeating: [ExtractedImage](), count: maxPage + 1)
        for pair  in pairs  { pairsByPage[pair.pageIndex].append(pair) }
        for image in images { imagesByPage[image.pageIndex].append(image) }

        var sections: [String] = []
        for pageIdx in 0...maxPage {
            let pagePairs  = pairsByPage[pageIdx]
            let pageImages = imagesByPage[pageIdx]
            guard !pagePairs.isEmpty || !pageImages.isEmpty else { continue }
            sections.append(buildSection(pageIdx: pageIdx, pairs: pagePairs, images: pageImages))
        }

        return buildHTML(sections: sections)
    }

    // MARK: - Private

    private func buildSection(
        pageIdx: Int,
        pairs: [TranslationPair],
        images: [ExtractedImage]
    ) -> String {
        let tableHTML: String
        if pairs.isEmpty {
            tableHTML = ""
        } else {
            let rows = pairs.map { pair in
                // <b>/<i> タグはHTMLとして直接出力
                "<tr><td class=\"orig\">\(pair.original)</td>" +
                "<td class=\"trans\">\(pair.translation)</td></tr>"
            }.joined(separator: "\n")

            tableHTML = """
            <table class="pair-table">
            <thead><tr><th>Original</th><th>翻訳</th></tr></thead>
            <tbody>\n\(rows)\n</tbody>
            </table>
            """
        }

        let imagesHTML: String
        if images.isEmpty {
            imagesHTML = ""
        } else {
            let figures = images.compactMap { img -> String? in
                guard let b64 = pngBase64(img.image) else { return nil }
                return "<figure class=\"page-image\">" +
                       "<img src=\"data:image/png;base64,\(b64)\" alt=\"\"></figure>"
            }.joined(separator: "\n")
            imagesHTML = figures.isEmpty ? "" : "<div class=\"images-row\">\n\(figures)\n</div>"
        }

        return """
        <section class="page-block">
        <p class="page-label">— Page \(pageIdx + 1) —</p>
        \(tableHTML)
        \(imagesHTML)
        </section>
        """
    }

    private func pngBase64(_ cgImage: CGImage) -> String? {
        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let data = rep.representation(using: .png, properties: [:]) else { return nil }
        return data.base64EncodedString()
    }

    private func buildHTML(sections: [String]) -> String {
        let css = """
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body {
            font-family: 'Helvetica Neue', Helvetica, Arial,
                         'Hiragino Sans', 'Hiragino Kaku Gothic ProN', sans-serif;
            font-size: 10pt;
            color: #111;
        }

        /* A4印刷設定: マージンは NSPrintInfo で設定済みのため CSS 側は 0 */
        @page { size: A4; margin: 0; }
        @media print { .page-block { page-break-inside: avoid; } }

        /* ページセクション */
        .page-block { margin-bottom: 14pt; border-bottom: 1px solid #e0e0e0; padding-bottom: 10pt; }
        .page-label { font-size: 7pt; color: #bbb; text-align: center; margin-bottom: 5pt; }

        /* 2カラムテーブル */
        .pair-table { width: 100%; border-collapse: collapse; table-layout: fixed; }
        .pair-table th {
            width: 50%; font-size: 8pt; font-weight: bold; color: #666;
            text-align: left; padding: 3pt 6pt;
            border-bottom: 1.5pt solid #aaa;
        }
        .pair-table td {
            width: 50%; vertical-align: top; padding: 4pt 6pt;
            border-bottom: 0.5pt solid #eee; line-height: 1.6; word-break: break-word;
        }
        .pair-table td.orig {
            font-family: 'Helvetica Neue', Helvetica, Arial, sans-serif;
            color: #333; border-right: 1pt solid #ddd;
        }
        .pair-table td.trans {
            font-family: 'Hiragino Sans', 'Hiragino Kaku Gothic ProN',
                         'Yu Gothic', 'Meiryo', sans-serif;
            color: #111;
        }

        /* 画像行: 2列・高さ制限でA4に6枚程度収まるサイズ */
        .images-row {
            display: flex; flex-wrap: wrap; gap: 8pt; margin-top: 10pt;
        }
        .page-image {
            flex: 1 1 45%; max-width: 45%;
        }
        .page-image img {
            max-width: 100%; max-height: 180pt;
            width: auto; height: auto;
            object-fit: contain; display: block;
            border: 0.5pt solid #ddd;
        }
        """

        return """
        <!DOCTYPE html>
        <html lang="ja">
        <head>
        <meta charset="utf-8">
        <style>\(css)</style>
        </head>
        <body>
        \(sections.joined(separator: "\n"))
        </body>
        </html>
        """
    }
}
