import Foundation
import PDFKit

// MARK: - Types

/// 翻訳の1ペア（原文 + 日本語訳）。pageIndex は JSON に含まれず translatePage() で付与する。
struct TranslationPair: Decodable {
    let original: String
    let translation: String
    var pageIndex: Int = 0

    private enum CodingKeys: String, CodingKey {
        case original, translation
    }
}

enum GeminiError: LocalizedError, Equatable {
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

    private let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent"

    /// 翻訳は1ページあたり最大300秒かかる場合があるためタイムアウトを長めに設定
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest  = 300
        config.timeoutIntervalForResource = 1800
        return URLSession(configuration: config)
    }()

    init() {}

    // MARK: - Public

    /// PDF を1ページずつ Gemini に送り、テキスト抽出と英→日翻訳を一括で行う。
    /// - Parameters:
    ///   - url: 翻訳対象のPDF URL（security-scoped resource は呼び出し元が開くこと）
    ///   - mode: 棒針 / かぎ針（プロンプトの文脈として使用）
    ///   - apiKey: Google AI Studio の API キー
    ///   - progressCallback: 0.0〜1.0 の進捗を受け取るクロージャ
    func translatePDF(
        at url: URL,
        mode: TranslationMode,
        apiKey: String,
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

            // 1ページずつ PDF に再構築して送信（ページ単位で進捗更新するため）
            let singlePageDoc = PDFDocument()
            singlePageDoc.insert(page, at: 0)
            guard let pageData = singlePageDoc.dataRepresentation() else { continue }

            let pairs = try await translatePage(
                pageData: pageData,
                pageNumber: pageIndex + 1,
                totalPages: pageCount,
                mode: mode,
                apiKey: apiKey
            )
            allPairs.append(contentsOf: pairs)

            await progressCallback?(Double(pageIndex + 1) / Double(pageCount))
        }

        return allPairs
    }

    // MARK: - Private: Network

    private func translatePage(
        pageData: Data,
        pageNumber: Int,
        totalPages: Int,
        mode: TranslationMode,
        apiKey: String
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

        var pairs = try parseResponse(data: data)
        // pageIndex は JSON に含まれないため、ここで注入する
        for i in pairs.indices { pairs[i].pageIndex = pageNumber - 1 }
        return pairs
    }

    // MARK: - Private: Request builder

    /// Gemini へ送信するリクエストボディを構築する。
    /// プロンプトはテキスト種別（パターン指示 vs 説明文）で段落化ルールを変え、
    /// <b>/<i> タグでフォントスタイルを保持し、ヘッダー/フッター・空行を除外するよう指示する。
    /// thinking モードは翻訳タスクでは不要かつ大幅な遅延原因になるため無効化する。
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
        - 太字の部分は <b>テキスト</b> で囲む
        - 斜体の部分は <i>テキスト</i> で囲む
        - 下線の部分は <u>テキスト</u> で囲む
        - セクション名・章タイトル（見出し）は <h>テキスト</h> で囲む
        - original と translation の両方に同じスタイルマークアップを適用する
        - 上記以外の HTML タグは使わないこと

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
                        ["inline_data": ["mime_type": "application/pdf", "data": base64PDF]],
                        ["text": prompt],
                    ]
                ]
            ],
            "generationConfig": [
                "thinkingConfig": ["thinkingBudget": 0]
            ],
        ]
    }

    // MARK: - Internal: Response parser (internal for testing)

    /// Gemini のレスポンス JSON から TranslationPair 配列を抽出する。
    /// Gemini は JSON の前後に markdown コードフェンスや余分な文言を付加することがあるため、
    /// 最初の `[` から最後の `]` までを切り出してデコードする。
    func parseResponse(data: Data) throws -> [TranslationPair] {
        struct GeminiResponse: Decodable {
            struct Candidate: Decodable {
                struct Content: Decodable {
                    struct Part: Decodable { let text: String? }
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

        // JSON配列部分を抽出（テキストなしページは [] を返す）
        guard let start = text.firstIndex(of: "["),
              let end   = text.lastIndex(of: "]") else {
            return []
        }

        guard let jsonData = String(text[start...end]).data(using: .utf8),
              let pairs = try? JSONDecoder().decode([TranslationPair].self, from: jsonData) else {
            return []
        }

        // 原文が空白のみのペアを除外（Gemini が稀に空エントリを含めることがある）
        return pairs.filter { !$0.original.trimmingCharacters(in: .whitespaces).isEmpty }
    }
}
