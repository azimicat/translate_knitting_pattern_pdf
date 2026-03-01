import AppKit
import CoreGraphics
import Foundation

// MARK: - Error

enum TypstError: LocalizedError {
    case typstNotFound
    case compilationFailed(String)

    var errorDescription: String? {
        switch self {
        case .typstNotFound:
            return "typst が見つかりません。ターミナルで brew install typst を実行してください。"
        case .compilationFailed(let msg):
            return "Typst コンパイルエラー: \(msg)"
        }
    }
}

// MARK: - TypstGenerator

actor TypstGenerator {

    // MARK: - Public

    func generate(pairs: [TranslationPair], to outputURL: URL) async throws {
        let typstPath = try findTypst()

        // 一時ディレクトリを作成
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("KnittingTranslator-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // .typ ソースを生成して書き出し
        let typContent = buildDocument(pairs: pairs)
        let inputURL = tempDir.appendingPathComponent("input.typ")
        try typContent.write(to: inputURL, atomically: true, encoding: .utf8)

        // typst compile を非同期実行
        try await runTypst(typstPath: typstPath, inputURL: inputURL, outputURL: outputURL)
    }

    // MARK: - Private: Process

    private func findTypst() throws -> String {
        let candidates = [
            "/opt/homebrew/bin/typst",  // Apple Silicon Homebrew
            "/usr/local/bin/typst",     // Intel Homebrew
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        throw TypstError.typstNotFound
    }

    private func runTypst(typstPath: String, inputURL: URL, outputURL: URL) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: typstPath)
        process.arguments = ["compile", inputURL.path, outputURL.path]

        let errorPipe = Pipe()
        process.standardError = errorPipe

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { p in
                if p.terminationStatus == 0 {
                    cont.resume()
                } else {
                    let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    let msg = String(data: data, encoding: .utf8) ?? "unknown error"
                    cont.resume(throwing: TypstError.compilationFailed(msg))
                }
            }
            do {
                try process.run()
            } catch {
                cont.resume(throwing: error)
            }
        }
    }

    // MARK: - Private: Typst document builder

    private func buildDocument(pairs: [TranslationPair]) -> String {
        let maxPage = pairs.map(\.pageIndex).max() ?? 0

        var pairsByPage = [[TranslationPair]](repeating: [], count: maxPage + 1)
        for p in pairs { pairsByPage[p.pageIndex].append(p) }

        var sections: [String] = []
        for pageIdx in 0...maxPage {
            let pagePairs = pairsByPage[pageIdx]
            guard !pagePairs.isEmpty else { continue }
            sections.append(buildTextSection(pageIdx: pageIdx, pairs: pagePairs))
        }

        return """
        #set page(paper: "a4", margin: (x: 12mm, y: 15mm))
        #set text(lang: "ja", font: ("Helvetica Neue", "Hiragino Sans", "Hiragino Kaku Gothic ProN"), size: 9.5pt)
        #set par(leading: 0.6em)
        #show table: set par(leading: 0.5em)

        \(sections.joined(separator: "\n\n#v(4pt)\n\n"))
        """
    }

    private func buildTextSection(pageIdx: Int, pairs: [TranslationPair]) -> String {
        var parts: [String] = []

        // ページラベル
        parts.append(#"#align(center)[#text(size: 7pt, fill: luma(180))[— Page \#(pageIdx + 1) —]]"#)

        let rows = pairs.map { pair -> String in
            let orig  = typstMarkup(pair.original,    font: "\"Helvetica Neue\"",         fill: "luma(60)")
            let trans = typstMarkup(pair.translation, font: "(\"Hiragino Sans\", \"Hiragino Kaku Gothic ProN\")", fill: "luma(0)")
            return "  [\(orig)], [\(trans)],"
        }.joined(separator: "\n")

        parts.append("""
        #table(
          columns: (1fr, 1fr),
          align: top,
          inset: (x: 5pt, y: 4pt),
          stroke: (x, y) => (
            left:   if x == 1 { 0.8pt + luma(210) } else { none },
            bottom: if y == 0 { 1.5pt + luma(170) } else { 0.4pt + luma(235) },
            top:    none,
            right:  none,
          ),
          table.header(
            text(weight: "bold", size: 8pt, fill: luma(100))[Original],
            text(weight: "bold", size: 8pt, fill: luma(100))[翻訳],
          ),
        \(rows)
        )
        """)

        return parts.joined(separator: "\n#v(4pt)\n")
    }


// MARK: - Private: Markup helpers

    /// <b>/<i> タグを Typst の #strong[]/#emph[] に変換し、特殊文字をエスケープする
    private func typstMarkup(_ text: String, font: String, fill: String) -> String {
        // まず <b>/<i> タグを Typst マークアップに変換
        let markup = convertTags(text)
        // フォントと色を外側の #text() で指定
        return "#text(font: \(font), fill: \(fill))[\(markup)]"
    }

    private func convertTags(_ text: String) -> String {
        var result = ""
        var isBold = false, isItalic = false
        var scanPos = text.startIndex
        var chunkStart = text.startIndex

        func flush(to end: String.Index) {
            guard chunkStart < end else { return }
            let raw = String(text[chunkStart..<end])
            let esc = escapeTypst(raw)
            switch (isBold, isItalic) {
            case (true,  true):  result += "#strong[#emph[\(esc)]]"
            case (true,  false): result += "#strong[\(esc)]"
            case (false, true):  result += "#emph[\(esc)]"
            case (false, false): result += esc
            }
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

    /// Typst コンテンツモードで特殊な意味を持つ文字をエスケープする
    private func escapeTypst(_ text: String) -> String {
        var s = text
        // バックスラッシュを最初にエスケープ（他のエスケープと順序注意）
        s = s.replacingOccurrences(of: "\\", with: "\\\\")
        s = s.replacingOccurrences(of: "*",  with: "\\*")  // 編み物パターンで頻出
        s = s.replacingOccurrences(of: "_",  with: "\\_")
        s = s.replacingOccurrences(of: "#",  with: "\\#")
        s = s.replacingOccurrences(of: "@",  with: "\\@")
        s = s.replacingOccurrences(of: "$",  with: "\\$")
        s = s.replacingOccurrences(of: "`",  with: "\\`")
        s = s.replacingOccurrences(of: "<",  with: "\\<")
        s = s.replacingOccurrences(of: ">",  with: "\\>")
        return s
    }
}
