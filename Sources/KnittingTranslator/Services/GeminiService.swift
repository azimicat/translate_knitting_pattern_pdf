import Foundation
import PDFKit

// MARK: - Types

struct TranslationPair: Decodable {
    let original: String
    let translation: String
}

enum GeminiError: LocalizedError {
    case pdfLoadFailed
    case apiError(statusCode: Int, body: String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .pdfLoadFailed:
            return "PDFの読み込みに失敗しました"
        case .apiError(let code, let body):
            return "Gemini API エラー (HTTP \(code)): \(body)"
        case .emptyResponse:
            return "Gemini API からの応答が空です"
        }
    }
}

// MARK: - GeminiService

actor GeminiService {
    private let apiKey: String
    private let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent"

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest  = 120
        config.timeoutIntervalForResource = 1800
        return URLSession(configuration: config)
    }()

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    /// PDFを1ページずつ Gemini に送り、抽出＋翻訳を一括で行う
    func translatePDF(
        at url: URL,
        mode: TranslationMode,
        progressCallback: ((Double) async -> Void)? = nil
    ) async throws -> [TranslationPair] {

        guard let document = PDFDocument(url: url) else {
            throw GeminiError.pdfLoadFailed
        }

        let pageCount = document.pageCount
        guard pageCount > 0 else { return [] }

        var allPairs: [TranslationPair] = []

        for pageIndex in 0..<pageCount {
            try Task.checkCancellation()

            guard let page = document.page(at: pageIndex) else { continue }

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
        let body = buildRequestBody(
            base64PDF: pageData.base64EncodedString(),
            mode: mode,
            pageNumber: pageNumber,
            totalPages: totalPages
        )

        var urlComponents = URLComponents(string: endpoint)!
        urlComponents.queryItems = [URLQueryItem(name: "key", value: apiKey)]

        var request = URLRequest(url: urlComponents.url!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let bodyText = String(data: data, encoding: .utf8) ?? "(no body)"
            throw GeminiError.apiError(statusCode: http.statusCode, body: bodyText)
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
        このPDFは\(modeDesc)パターンの \(pageNumber)/\(totalPages) ページです。
        本文テキストを英語から日本語へ翻訳してください。

        テキストの種類によってグループ化のルールを変えてください：

        【パターン部分（編み方の指示）】
        例: "Row 1: K2, P2, *K4; rep from *", "Round 3: sc in each st"
        → 1文（1つの編み指示、または意味のひとまとまり）ごとに1要素にする
        → 途中で改行されていても同一の指示なら1要素にまとめる

        【パターン以外の部分（説明文・材料・注意書きなど）】
        例: 素材の説明、ゲージ情報、完成サイズ、作り方の注意
        → 意味のまとまり（段落・ブロック）ごとに1要素にする
        → 複数行でも同じ段落・話題であれば1要素にまとめる

        フォントスタイルの保持：
        - 原文PDFで太字の部分は <b>テキスト</b> で囲む
        - 原文PDFで斜体の部分は <i>テキスト</i> で囲む
        - originalとtranslationの両方に同じスタイルマークアップを適用する

        共通ルール：
        - ページ番号・ヘッダー・フッターは除外する
        - 空行は除外する
        - このページにテキストがない場合は空配列 [] を返す
        - 他の文言は一切出力せず、JSON配列だけを返すこと

        出力形式（JSON配列のみ）:
        [{"original": "英語の<b>原文</b>", "translation": "日本語の<b>訳</b>"}, ...]
        """

        return [
            "contents": [
                [
                    "parts": [
                        [
                            "inline_data": [
                                "mime_type": "application/pdf",
                                "data": base64PDF
                            ]
                        ],
                        [
                            "text": prompt
                        ]
                    ]
                ]
            ]
        ]
    }

    private func parseResponse(data: Data) throws -> [TranslationPair] {
        struct GeminiResponse: Decodable {
            struct Candidate: Decodable {
                struct Content: Decodable {
                    struct Part: Decodable {
                        let text: String?
                    }
                    let parts: [Part]
                }
                let content: Content
            }
            let candidates: [Candidate]
        }

        let decoded = try JSONDecoder().decode(GeminiResponse.self, from: data)
        guard let text = decoded.candidates.first?.content.parts.first?.text,
              !text.isEmpty else {
            throw GeminiError.emptyResponse
        }

        // JSON配列部分を抽出
        guard let start = text.firstIndex(of: "["),
              let end   = text.lastIndex(of: "]") else {
            return []  // テキストなしページは空配列
        }
        let jsonSlice = String(text[start...end])

        guard let jsonData = jsonSlice.data(using: .utf8),
              let pairs = try? JSONDecoder().decode([TranslationPair].self, from: jsonData) else {
            return []
        }

        return pairs.filter {
            !$0.original.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }
}
