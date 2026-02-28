import Foundation
import PDFKit

// MARK: - Errors

enum ClaudeError: LocalizedError {
    case pdfLoadFailed
    case apiError(statusCode: Int, body: String)
    case emptyResponse
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .pdfLoadFailed:
            return "PDFの読み込みに失敗しました"
        case .apiError(let code, let body):
            return "Claude API エラー (HTTP \(code)): \(body)"
        case .emptyResponse:
            return "Claude API からの応答が空です"
        case .parseError(let detail):
            return "翻訳結果の解析に失敗しました: \(detail)"
        }
    }
}

// MARK: - Result type

struct TranslationPair: Decodable {
    let original: String
    let translation: String
}

// MARK: - ClaudeService

actor ClaudeService {
    private let apiKey: String
    private let model = "claude-opus-4-6"
    private let endpoint = "https://api.anthropic.com/v1/messages"

    // タイムアウトを延長した専用セッション
    // request: 1ページあたり最大180秒、resource: 全体で30分
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest  = 180
        config.timeoutIntervalForResource = 1800
        return URLSession(configuration: config)
    }()

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    /// PDFを1ページずつ Claude に送信して翻訳する
    func translatePDF(
        at url: URL,
        mode: TranslationMode,
        progressCallback: ((Double) async -> Void)? = nil
    ) async throws -> [TranslationPair] {

        guard let document = PDFDocument(url: url) else {
            throw ClaudeError.pdfLoadFailed
        }

        let pageCount = document.pageCount
        guard pageCount > 0 else { return [] }

        var allPairs: [TranslationPair] = []

        for pageIndex in 0..<pageCount {
            try Task.checkCancellation()

            guard let page = document.page(at: pageIndex) else { continue }

            // 1ページ分の PDF データを生成
            let singlePageDoc = PDFDocument()
            singlePageDoc.insert(page, at: 0)
            guard let pageData = singlePageDoc.dataRepresentation() else { continue }

            let pairs = try await translatePage(
                pageData: pageData,
                pageNumber: pageIndex + 1,
                totalPages: pageCount,
                mode: mode
            )
            allPairs.append(contentsOf: pairs)

            // ページ完了ごとに進捗を更新
            await progressCallback?(Double(pageIndex + 1) / Double(pageCount))
        }

        return allPairs
    }

    // MARK: - Private

    private func translatePage(
        pageData: Data,
        pageNumber: Int,
        totalPages: Int,
        mode: TranslationMode
    ) async throws -> [TranslationPair] {
        let base64PDF = pageData.base64EncodedString()
        let body = buildRequestBody(base64PDF: base64PDF, mode: mode,
                                    pageNumber: pageNumber, totalPages: totalPages)

        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey,             forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01",       forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let bodyText = String(data: data, encoding: .utf8) ?? "(no body)"
            throw ClaudeError.apiError(statusCode: http.statusCode, body: bodyText)
        }

        return try parseResponse(data: data)
    }

    private func buildRequestBody(
        base64PDF: String,
        mode: TranslationMode,
        pageNumber: Int,
        totalPages: Int
    ) -> [String: Any] {
        let modeDesc = mode == .knitting ? "棒針編み（knitting）" : "かぎ針編み（crochet）"
        let prompt = """
        このPDFは\(modeDesc)のパターン（編み図・手順書）の \(pageNumber)/\(totalPages) ページです。
        このページの本文を英語から日本語へ、1行ずつ翻訳してください。

        ルール：
        - ページ番号・ヘッダー・フッター・図の説明文は除外する
        - 空行は除外する
        - 専門用語（k, p, yo, k2tog, sc, dc など）は正確な日本語訳を使う
        - このページに翻訳すべきテキストがない場合は空配列 [] を返す
        - 他の説明文は一切出力せず、以下のJSON配列だけを返すこと

        出力形式（JSON配列のみ）:
        [
          {"original": "英語の原文", "translation": "日本語訳"},
          {"original": "英語の原文", "translation": "日本語訳"}
        ]
        """

        return [
            "model": model,
            "max_tokens": 4096,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "document",
                            "source": [
                                "type": "base64",
                                "media_type": "application/pdf",
                                "data": base64PDF
                            ]
                        ],
                        [
                            "type": "text",
                            "text": prompt
                        ]
                    ]
                ]
            ]
        ]
    }

    private func parseResponse(data: Data) throws -> [TranslationPair] {
        struct ClaudeResponse: Decodable {
            struct Content: Decodable {
                let type: String
                let text: String?
            }
            let content: [Content]
        }

        let decoded = try JSONDecoder().decode(ClaudeResponse.self, from: data)
        guard let text = decoded.content.first(where: { $0.type == "text" })?.text,
              !text.isEmpty else {
            throw ClaudeError.emptyResponse
        }

        // マークダウンコードブロック等からJSON配列部分を抽出
        guard let start = text.firstIndex(of: "["),
              let end   = text.lastIndex(of: "]") else {
            // テキストがない正常ケース（画像のみのページなど）は空配列を返す
            return []
        }
        let jsonSlice = String(text[start...end])

        guard let jsonData = jsonSlice.data(using: .utf8) else {
            throw ClaudeError.parseError("UTF-8変換失敗")
        }

        do {
            return try JSONDecoder().decode([TranslationPair].self, from: jsonData)
        } catch {
            throw ClaudeError.parseError(error.localizedDescription)
        }
    }
}
