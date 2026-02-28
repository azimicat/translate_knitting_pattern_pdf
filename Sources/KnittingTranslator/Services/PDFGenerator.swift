import AppKit
import CoreGraphics
import CoreText
import Foundation

enum PDFError: LocalizedError {
    case contextCreationFailed
    var errorDescription: String? { "PDFコンテキストの作成に失敗しました" }
}

actor PDFGenerator {
    private let pageW:  CGFloat = 595   // A4 幅 pt
    private let pageH:  CGFloat = 842   // A4 高さ pt
    private let margin: CGFloat = 45    // 余白
    private let colGap: CGFloat = 8     // 列間隔
    private var colW:   CGFloat { (pageW - 2 * margin - colGap) / 2 }  // ≈ 247pt

    // MARK: - Public

    func generate(pairs: [TranslationPair], images: [ExtractedImage], to url: URL) async throws {
        var box = CGRect(x: 0, y: 0, width: pageW, height: pageH)
        guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else {
            throw PDFError.contextCreationFailed
        }

        let origFont  = NSFont(name: "Helvetica", size: 9.5)
                     ?? NSFont.systemFont(ofSize: 9.5)
        let transFont = NSFont(name: "HiraginoSans-W3", size: 9.5)
                     ?? NSFont(name: "Hiragino Sans", size: 9.5)
                     ?? NSFont.systemFont(ofSize: 9.5)

        // ソースページごとにグルーピング
        let maxPage = max(pairs.map(\.pageIndex).max() ?? 0,
                          images.map(\.pageIndex).max() ?? 0)
        var pairsByPage  = [[TranslationPair]](repeating: [], count: maxPage + 1)
        var imagesByPage = [[ExtractedImage]](repeating: [], count: maxPage + 1)
        for p in pairs  { pairsByPage[p.pageIndex].append(p) }
        for i in images { imagesByPage[i.pageIndex].append(i) }

        ctx.beginPage(mediaBox: &box)
        var y = pageH - margin

        // 最初のカラムヘッダー
        drawColumnHeaders(ctx: ctx, y: &y, origFont: origFont, transFont: transFont)

        for srcPage in 0...maxPage {
            // ── テキストペア ──
            for pair in pairsByPage[srcPage] {
                let oStr = attributed(pair.original,    baseFont: origFont,  color: .darkGray)
                let tStr = attributed(pair.translation, baseFont: transFont, color: .black)

                let oH   = measuredHeight(oStr, width: colW)
                let tH   = measuredHeight(tStr, width: colW)
                let rowH = max(oH, tH) + 5

                if y - rowH < margin {
                    ctx.endPage()
                    ctx.beginPage(mediaBox: &box)
                    y = pageH - margin
                    drawColumnHeaders(ctx: ctx, y: &y, origFont: origFont, transFont: transFont)
                }

                let leftRect  = CGRect(x: margin,                 y: y - rowH, width: colW, height: rowH)
                let rightRect = CGRect(x: margin + colW + colGap, y: y - rowH, width: colW, height: rowH)
                drawAttributedString(oStr, in: leftRect,  ctx: ctx)
                drawAttributedString(tStr, in: rightRect, ctx: ctx)
                drawVLine(ctx: ctx, x: margin + colW + colGap / 2, y1: y, y2: y - rowH)
                drawHLine(ctx: ctx, y: y - rowH, alpha: 0.15)
                y -= rowH
            }

            // ── 画像（2列グリッド）──
            let imgs = imagesByPage[srcPage]
            guard !imgs.isEmpty else { continue }

            let slotH: CGFloat = 155
            var col = 0
            for img in imgs {
                if col == 0 && y - slotH - 10 < margin {
                    ctx.endPage()
                    ctx.beginPage(mediaBox: &box)
                    y = pageH - margin
                }
                let imgW = CGFloat(img.image.width)
                let imgH = CGFloat(img.image.height)
                let scale = min(colW / imgW, slotH / imgH, 1.0)
                let dW = imgW * scale, dH = imgH * scale
                let x: CGFloat = col == 0 ? margin : margin + colW + colGap
                ctx.draw(img.image, in: CGRect(x: x + (colW - dW) / 2, y: y - dH, width: dW, height: dH))
                col += 1
                if col >= 2 { col = 0; y -= (slotH + 6) }
            }
            if col > 0 { y -= (slotH + 6) }
            y -= 4
        }

        ctx.endPage()
        ctx.closePDF()
    }

    // MARK: - Text helpers

    /// <b>/<i> タグをパースして NSAttributedString を生成する
    private func attributed(_ text: String, baseFont: NSFont, color: NSColor) -> NSAttributedString {
        let result  = NSMutableAttributedString()
        let manager = NSFontManager.shared
        var isBold = false, isItalic = false
        var scanPos    = text.startIndex
        var chunkStart = text.startIndex

        func flush(to end: String.Index) {
            guard chunkStart < end else { return }
            let chunk = String(text[chunkStart..<end])
            let font  = styledFont(base: baseFont, bold: isBold, italic: isItalic, manager: manager)
            result.append(NSAttributedString(string: chunk,
                attributes: [.font: font, .foregroundColor: color]))
        }

        while scanPos < text.endIndex {
            guard text[scanPos] == "<" else { scanPos = text.index(after: scanPos); continue }
            let rest = text[scanPos...]
            var tagLen = 0; var nb = isBold; var ni = isItalic
            if      rest.hasPrefix("<b>")  { tagLen = 3; nb = true  }
            else if rest.hasPrefix("</b>") { tagLen = 4; nb = false }
            else if rest.hasPrefix("<i>")  { tagLen = 3; ni = true  }
            else if rest.hasPrefix("</i>") { tagLen = 4; ni = false }
            else { scanPos = text.index(after: scanPos); continue }
            flush(to: scanPos)
            isBold = nb; isItalic = ni
            scanPos    = text.index(scanPos, offsetBy: tagLen)
            chunkStart = scanPos
        }
        flush(to: text.endIndex)
        return result
    }

    private func styledFont(base: NSFont, bold: Bool, italic: Bool,
                             manager: NSFontManager) -> NSFont {
        guard bold || italic else { return base }
        var f = base
        if bold   { f = manager.convert(f, toHaveTrait: .boldFontMask)   }
        if italic { f = manager.convert(f, toHaveTrait: .italicFontMask) }
        return f
    }

    private func measuredHeight(_ str: NSAttributedString, width: CGFloat) -> CGFloat {
        let fs = CTFramesetterCreateWithAttributedString(str)
        let sz = CTFramesetterSuggestFrameSizeWithConstraints(
            fs, CFRange(location: 0, length: str.length), nil,
            CGSize(width: width, height: .greatestFiniteMagnitude), nil)
        return ceil(sz.height) + 2
    }

    private func drawAttributedString(_ str: NSAttributedString, in rect: CGRect, ctx: CGContext) {
        let path = CGPath(rect: rect, transform: nil)
        let fs   = CTFramesetterCreateWithAttributedString(str)
        let frame = CTFramesetterCreateFrame(
            fs, CFRange(location: 0, length: str.length), path, nil)
        CTFrameDraw(frame, ctx)
    }

    // MARK: - Drawing helpers

    private func drawColumnHeaders(ctx: CGContext, y: inout CGFloat,
                                    origFont: NSFont, transFont: NSFont) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 8),
            .foregroundColor: NSColor.gray
        ]
        drawAttributedString(
            NSAttributedString(string: "Original", attributes: attrs),
            in: CGRect(x: margin, y: y - 12, width: colW, height: 14), ctx: ctx)
        drawAttributedString(
            NSAttributedString(string: "翻訳", attributes: attrs),
            in: CGRect(x: margin + colW + colGap, y: y - 12, width: colW, height: 14), ctx: ctx)

        // ヘッダー下の区切り線
        ctx.setStrokeColor(NSColor.gray.cgColor)
        ctx.setLineWidth(0.75)
        ctx.move(to: CGPoint(x: margin, y: y - 14))
        ctx.addLine(to: CGPoint(x: pageW - margin, y: y - 14))
        ctx.strokePath()
        y -= 16
    }

    private func drawVLine(ctx: CGContext, x: CGFloat, y1: CGFloat, y2: CGFloat) {
        ctx.setStrokeColor(NSColor(white: 0.75, alpha: 1).cgColor)
        ctx.setLineWidth(0.5)
        ctx.move(to: CGPoint(x: x, y: y1))
        ctx.addLine(to: CGPoint(x: x, y: y2))
        ctx.strokePath()
    }

    private func drawHLine(ctx: CGContext, y: CGFloat, alpha: CGFloat) {
        ctx.setStrokeColor(NSColor(white: 0, alpha: alpha).cgColor)
        ctx.setLineWidth(0.4)
        ctx.move(to: CGPoint(x: margin, y: y))
        ctx.addLine(to: CGPoint(x: pageW - margin, y: y))
        ctx.strokePath()
    }
}
