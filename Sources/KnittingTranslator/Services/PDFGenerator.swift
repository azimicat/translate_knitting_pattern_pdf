import CoreGraphics
import CoreText
import AppKit
import Foundation

enum PDFError: LocalizedError {
    case contextCreationFailed

    var errorDescription: String? {
        switch self {
        case .contextCreationFailed: return "PDFコンテキストの作成に失敗しました"
        }
    }
}

actor PDFGenerator {
    private let pageW: CGFloat = 595
    private let pageH: CGFloat = 842
    private let margin: CGFloat = 50

    func generate(
        originals: [String],
        translated: [String],
        images: [ExtractedImage],
        to url: URL
    ) async throws {
        var mediaBox = CGRect(x: 0, y: 0, width: pageW, height: pageH)
        guard let ctx = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
            throw PDFError.contextCreationFailed
        }

        // Build single NSAttributedString: interleaved originals + translations
        let fullString = buildAttributedString(originals: originals, translated: translated)
        let framesetter = CTFramesetterCreateWithAttributedString(fullString)

        // Paginate text across A4 pages
        let textRect = CGRect(
            x: margin,
            y: margin,
            width: pageW - 2 * margin,
            height: pageH - 2 * margin
        )
        var currentPos = 0
        let totalLen = CFAttributedStringGetLength(fullString)

        while currentPos < totalLen {
            ctx.beginPage(mediaBox: &mediaBox)

            let path = CGPath(rect: textRect, transform: nil)
            // length: 0 = fill as much as possible from currentPos
            let frame = CTFramesetterCreateFrame(
                framesetter,
                CFRange(location: currentPos, length: 0),
                path,
                nil
            )
            CTFrameDraw(frame, ctx)

            // CTFrameGetVisibleStringRange tells us exactly how many chars were drawn
            let visible = CTFrameGetVisibleStringRange(frame)
            if visible.length == 0 { break }  // safety: avoid infinite loop
            currentPos += visible.length

            ctx.endPage()
        }

        // Image pages (max 6 per page in 2×3 grid)
        if !images.isEmpty {
            addImagePages(images: images, ctx: ctx, mediaBox: &mediaBox)
        }

        ctx.closePDF()
    }

    private func buildAttributedString(originals: [String], translated: [String]) -> CFAttributedString {
        let result = NSMutableAttributedString()

        let origFont  = NSFont(name: "Helvetica", size: 10) ?? NSFont.systemFont(ofSize: 10)
        let transFont = NSFont(name: "HiraginoSans-W3", size: 10)
                     ?? NSFont(name: "Hiragino Sans", size: 10)
                     ?? NSFont.systemFont(ofSize: 10)
        let labelFont = NSFont.boldSystemFont(ofSize: 8)

        let newline    = NSAttributedString(string: "\n",   attributes: [.font: origFont])
        let dblNewline = NSAttributedString(string: "\n\n", attributes: [.font: transFont])
        let labelAttrs: [NSAttributedString.Key: Any] = [.font: labelFont, .foregroundColor: NSColor.gray]

        for (orig, trans) in zip(originals, translated) {
            result.append(NSAttributedString(string: "【原文】\n", attributes: labelAttrs))
            result.append(attributed(from: orig,  baseFont: origFont,  color: .darkGray))
            result.append(newline)
            result.append(NSAttributedString(string: "【翻訳】\n", attributes: labelAttrs))
            result.append(attributed(from: trans, baseFont: transFont, color: .black))
            result.append(dblNewline)
        }
        return result
    }

    /// <b>...</b> / <i>...</i> タグをパースして太字・斜体フォントを適用した NSAttributedString を返す
    private func attributed(from text: String, baseFont: NSFont, color: NSColor) -> NSAttributedString {
        let result  = NSMutableAttributedString()
        let manager = NSFontManager.shared
        var isBold   = false
        var isItalic = false
        var scanPos   = text.startIndex
        var chunkStart = text.startIndex

        while scanPos < text.endIndex {
            guard text[scanPos] == "<" else {
                scanPos = text.index(after: scanPos)
                continue
            }
            let rest = text[scanPos...]
            var tagLen  = 0
            var newBold   = isBold
            var newItalic = isItalic

            if      rest.hasPrefix("<b>")  { tagLen = 3; newBold   = true  }
            else if rest.hasPrefix("</b>") { tagLen = 4; newBold   = false }
            else if rest.hasPrefix("<i>")  { tagLen = 3; newItalic = true  }
            else if rest.hasPrefix("</i>") { tagLen = 4; newItalic = false }
            else { scanPos = text.index(after: scanPos); continue }

            // タグ前のテキストを現在のスタイルで追加
            if chunkStart < scanPos {
                let chunk = String(text[chunkStart..<scanPos])
                let font  = styledFont(base: baseFont, bold: isBold, italic: isItalic, manager: manager)
                result.append(NSAttributedString(string: chunk, attributes: [.font: font, .foregroundColor: color]))
            }
            isBold   = newBold
            isItalic = newItalic
            scanPos    = text.index(scanPos, offsetBy: tagLen)
            chunkStart = scanPos
        }

        // 残りのテキストを追加
        if chunkStart < text.endIndex {
            let chunk = String(text[chunkStart...])
            let font  = styledFont(base: baseFont, bold: isBold, italic: isItalic, manager: manager)
            result.append(NSAttributedString(string: chunk, attributes: [.font: font, .foregroundColor: color]))
        }
        return result
    }

    private func styledFont(base: NSFont, bold: Bool, italic: Bool, manager: NSFontManager) -> NSFont {
        guard bold || italic else { return base }
        var font = base
        if bold   { font = manager.convert(font, toHaveTrait: .boldFontMask)   }
        if italic { font = manager.convert(font, toHaveTrait: .italicFontMask) }
        return font
    }

    // 2-column × 3-row grid, 6 images per page
    private func addImagePages(images: [ExtractedImage], ctx: CGContext, mediaBox: inout CGRect) {
        let slotW = (pageW - 2 * margin - 10) / 2   // ~247.5pt
        let slotH = (pageH - 2 * margin - 20) / 3   // ~247.3pt
        var col = 0
        var row = 0

        ctx.beginPage(mediaBox: &mediaBox)

        for img in images {
            let imgW = CGFloat(img.image.width)
            let imgH = CGFloat(img.image.height)
            let scale = min(slotW / imgW, slotH / imgH)
            let drawW = imgW * scale
            let drawH = imgH * scale

            // Skip if rendered long side ≤ 80pt
            guard max(drawW, drawH) > 80 else { continue }

            let x = margin + CGFloat(col) * (slotW + 5)
            let y = margin + CGFloat(2 - row) * (slotH + 10)  // y-up: row 0 = bottom slot
            let destRect = CGRect(
                x: x + (slotW - drawW) / 2,
                y: y + (slotH - drawH) / 2,
                width: drawW,
                height: drawH
            )
            ctx.draw(img.image, in: destRect)

            col += 1
            if col >= 2 { col = 0; row += 1 }
            if row >= 3 {
                ctx.endPage()
                ctx.beginPage(mediaBox: &mediaBox)
                col = 0
                row = 0
            }
        }
        ctx.endPage()
    }
}
