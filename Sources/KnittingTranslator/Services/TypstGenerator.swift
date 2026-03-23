import Foundation

// MARK: - Error

enum TypstError: LocalizedError {
    case typstNotFound
    case compilationFailed(String)

    var errorDescription: String? {
        switch self {
        case .typstNotFound:
            return "アプリに同梱された typst バイナリが見つかりません。アプリを再インストールしてください。"
        case .compilationFailed(let msg):
            return "Typst コンパイルエラー: \(msg)"
        }
    }
}

// MARK: - TypstGenerator

/// TranslationPair 配列から Typst ソースを生成し、typst CLI でバイリンガル PDF にコンパイルする。
actor TypstGenerator {

    // MARK: - Public

    /// pairs を2カラム（左=原文 / 右=翻訳）の A4 PDF として outputURL に書き出す。
    func generate(pairs: [TranslationPair], to outputURL: URL) async throws {
        let typstPath = try findTypst()

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("KnittingTranslator-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let inputURL = tempDir.appendingPathComponent("input.typ")
        try buildDocument(pairs: pairs).write(to: inputURL, atomically: true, encoding: .utf8)

        try await runTypst(typstPath: typstPath, inputURL: inputURL, outputURL: outputURL)
    }

    // MARK: - Private: Process

    /// バンドル内の typst バイナリを一時ディレクトリにコピーして実行可能パスを返す。
    /// バンドルに見つからない場合は Homebrew パスにフォールバックする（開発時用）。
    func findTypst() throws -> String {
        // バンドル内バイナリを優先
        //
        // 検索順:
        // 1. Contents/Resources/Bundle.bundle — 配布版 .app の標準位置（codesign 対応）
        // 2. Bundle.module — テスト・開発時: SPM が生成したハードコード dev パスへのフォールバック
        //    ※ app として実行される場合は (1) で必ず見つかるため (2) に到達せず
        //      fatalError のリスクはない
        let spmBundleName = "KnittingTranslator_KnittingTranslator.bundle"
        let typstFromResources = Bundle.main.resourceURL
            .flatMap { Bundle(url: $0.appendingPathComponent(spmBundleName)) }?
            .url(forResource: "typst", withExtension: nil)
        if let bundleURL = typstFromResources ?? Bundle.module.url(forResource: "typst", withExtension: nil) {
            let cachedPath = "/tmp/KnittingTranslator-typst/typst"
            let fm = FileManager.default

            var needsCopy = true
            if fm.isExecutableFile(atPath: cachedPath) {
                // 更新日時を比較して不要なコピーをスキップ
                let bundleMod = (try? fm.attributesOfItem(atPath: bundleURL.path)[.modificationDate]) as? Date
                let cacheMod  = (try? fm.attributesOfItem(atPath: cachedPath)[.modificationDate]) as? Date
                if let b = bundleMod, let c = cacheMod, c >= b {
                    needsCopy = false
                }
            }

            if needsCopy {
                let cacheDir = URL(fileURLWithPath: "/tmp/KnittingTranslator-typst")
                try? fm.createDirectory(at: cacheDir, withIntermediateDirectories: true)
                let destURL = cacheDir.appendingPathComponent("typst")
                try? fm.removeItem(at: destURL)
                try fm.copyItem(at: bundleURL, to: destURL)
                try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cachedPath)
            }

            return cachedPath
        }

        // フォールバック: Homebrew（開発環境用）
        let candidates = [
            "/opt/homebrew/bin/typst",  // Apple Silicon
            "/usr/local/bin/typst",     // Intel
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        throw TypstError.typstNotFound
    }

    /// `typst compile <input> <output>` を非同期実行する。
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

    // MARK: - Private: Document builder

    /// ページごとにセクションを生成し、Typst ドキュメント全体を返す。
    private func buildDocument(pairs: [TranslationPair]) -> String {
        let maxPage = pairs.map(\.pageIndex).max() ?? 0

        var pairsByPage = [[TranslationPair]](repeating: [], count: maxPage + 1)
        for p in pairs { pairsByPage[p.pageIndex].append(p) }

        let sections = (0...maxPage).compactMap { idx -> String? in
            let pagePairs = pairsByPage[idx]
            guard !pagePairs.isEmpty else { return nil }
            return buildSection(pageIdx: idx, pairs: pagePairs)
        }

        return """
        #set page(paper: "a4", margin: (x: 12mm, y: 15mm))
        #set text(lang: "ja", font: ("Helvetica Neue", "Hiragino Sans", "Hiragino Kaku Gothic ProN"), size: 9.5pt)
        #set par(leading: 0.6em)
        #show table: set par(leading: 0.5em)

        \(sections.joined(separator: "\n\n#v(4pt)\n\n"))
        """
    }

    /// 1ページ分のヘッダー + 翻訳テーブルを Typst ソースとして返す。
    private func buildSection(pageIdx: Int, pairs: [TranslationPair]) -> String {
        let pageLabel = #"#align(center)[#text(size: 7pt, fill: luma(180))[— Page \#(pageIdx + 1) —]]"#

        let rows = pairs.map { pair -> String in
            let orig  = typstMarkup(pair.original,    font: "\"Helvetica Neue\"",                              fill: "luma(60)")
            let trans = typstMarkup(pair.translation, font: "(\"Hiragino Sans\", \"Hiragino Kaku Gothic ProN\")", fill: "luma(0)")
            return "  [\(orig)], [\(trans)],"
        }.joined(separator: "\n")

        let table = """
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
        """

        return [pageLabel, table].joined(separator: "\n#v(4pt)\n")
    }

    // MARK: - Internal: Markup helpers (internal for testing)

    /// テキストの <b>/<i> タグを Typst マークアップに変換し、#text() でフォント・色を指定して返す。
    func typstMarkup(_ text: String, font: String, fill: String) -> String {
        "#text(font: \(font), fill: \(fill))[\(convertTags(text))]"
    }

    /// <b>/<i>/<u>/<h> タグを Typst の #strong[]/#emph[]/#underline[]/#text(weight:"bold")[] に変換する。
    ///
    /// 状態機械: isBold / isItalic / isUnderline / isHeading フラグでスタイル状態を保持しながら
    /// 文字列を1パスで走査する。タグを検出するたびに直前のチャンクをフラッシュし、
    /// 新しいスタイル状態で続きを処理する。
    func convertTags(_ text: String) -> String {
        var result = ""
        var isBold = false, isItalic = false, isUnderline = false, isHeading = false
        var scanPos = text.startIndex
        var chunkStart = text.startIndex

        /// 現在のスタイル状態で chunkStart..<end をフラッシュする
        /// ネスト順（内→外）: italic → underline → bold → heading
        func flush(to end: String.Index) {
            guard chunkStart < end else { return }
            let esc = escapeTypst(String(text[chunkStart..<end]))
            var s = esc
            if isItalic    { s = "#emph[\(s)]" }
            if isUnderline { s = "#underline[\(s)]" }
            if isBold      { s = "#strong[\(s)]" }
            if isHeading   { s = "#text(size: 10pt, weight: \"bold\")[\(s)]" }
            result += s
        }

        while scanPos < text.endIndex {
            guard text[scanPos] == "<" else { scanPos = text.index(after: scanPos); continue }

            let rest = text[scanPos...]
            var tagLen = 0
            var nb = isBold, ni = isItalic, nu = isUnderline, nh = isHeading

            if      rest.hasPrefix("<b>")  { tagLen = 3; nb = true  }
            else if rest.hasPrefix("</b>") { tagLen = 4; nb = false }
            else if rest.hasPrefix("<i>")  { tagLen = 3; ni = true  }
            else if rest.hasPrefix("</i>") { tagLen = 4; ni = false }
            else if rest.hasPrefix("<u>")  { tagLen = 3; nu = true  }
            else if rest.hasPrefix("</u>") { tagLen = 4; nu = false }
            else if rest.hasPrefix("<h>")  { tagLen = 3; nh = true  }
            else if rest.hasPrefix("</h>") { tagLen = 4; nh = false }
            else { scanPos = text.index(after: scanPos); continue }

            flush(to: scanPos)
            isBold = nb; isItalic = ni; isUnderline = nu; isHeading = nh
            scanPos    = text.index(scanPos, offsetBy: tagLen)
            chunkStart = scanPos
        }
        flush(to: text.endIndex)
        return result
    }

    /// Typst のコンテンツモードで特殊な意味を持つ文字をエスケープする。
    /// バックスラッシュを最初に処理しないと二重エスケープになるため順序が重要。
    /// `*` は編み物パターン（`*K2, P2; rep from *`）で頻出するため必須。
    func escapeTypst(_ text: String) -> String {
        var s = text
        s = s.replacingOccurrences(of: "\\", with: "\\\\")  // 最初に処理（順序重要）
        s = s.replacingOccurrences(of: "*",  with: "\\*")
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
