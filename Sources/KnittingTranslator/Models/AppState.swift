import PDFKit
import SwiftUI

@MainActor
@Observable
final class AppState {
    var mode: TranslationMode = .knitting
    var ignoreImages: Bool = false
    var droppedURL: URL? = nil
    var originalFileName: String = ""
    var errorMessage: String? = nil
    var isProcessing: Bool = false
    var progress: Double = 0
    var progressLabel: String = ""
    var generatedDocument: PDFDocument? = nil

    private let geminiService: GeminiService
    private let imageExtractor = ImageExtractor()
    private var translationTask: Task<Void, Never>?

    init() {
        let key = EnvLoader.googleAIAPIKey() ?? ""
        self.geminiService = GeminiService(apiKey: key)

        if key.isEmpty {
            self.errorMessage = "Google AI APIキーが未設定です。プロジェクト直下の .env に GOOGLE_AI_API_KEY を設定してください。"
        }
    }

    func processTranslation() async {
        guard let url = droppedURL else { return }
        let mode = self.mode
        let ignoreImages = self.ignoreImages

        isProcessing = true
        progress = 0
        errorMessage = nil

        translationTask = Task { [weak self] in
            guard let self else { return }
            do {
                // 1. Security-scoped access
                guard url.startAccessingSecurityScopedResource() else {
                    throw AppError.fileAccessDenied
                }
                defer { url.stopAccessingSecurityScopedResource() }

                // 2. Gemini でテキスト抽出＋翻訳（0.00→0.80）
                progressLabel = "Gemini で翻訳中..."
                let pairs = try await geminiService.translatePDF(
                    at: url,
                    mode: mode
                ) { [weak self] p in
                    await MainActor.run {
                        self?.progress = p * 0.80
                        self?.progressLabel = String(format: "Gemini で翻訳中... %.0f%%", p * 100)
                    }
                }
                progress = 0.80

                let originals   = pairs.map(\.original)
                let translated  = pairs.map(\.translation)

                // 3. 画像抽出（0.80→0.90）
                progressLabel = "画像を抽出中..."
                let images: [ExtractedImage] = ignoreImages ? [] :
                    (try? await imageExtractor.extractImages(from: url)) ?? []
                progress = 0.90

                // 4. PDF 生成（0.90→1.00）
                progressLabel = "PDFを生成中..."
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString + ".pdf")
                try await PDFGenerator().generate(
                    originals: originals,
                    translated: translated,
                    images: images,
                    to: tempURL
                )

                generatedDocument = PDFDocument(url: tempURL)
                progress = 1.0
                progressLabel = "完了"

            } catch {
                errorMessage = error.localizedDescription
            }
            isProcessing = false
        }
    }

    func cancelTranslation() {
        translationTask?.cancel()
        translationTask = nil
        isProcessing = false
    }
}

enum AppError: LocalizedError {
    case fileAccessDenied

    var errorDescription: String? {
        switch self {
        case .fileAccessDenied: return "ファイルへのアクセス権限がありません"
        }
    }
}
