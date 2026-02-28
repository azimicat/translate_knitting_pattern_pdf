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

    private let claudeService: ClaudeService
    private let imageExtractor = ImageExtractor()
    private var translationTask: Task<Void, Never>?

    init() {
        let key = EnvLoader.anthropicAPIKey() ?? ""
        self.claudeService = ClaudeService(apiKey: key)
        if key.isEmpty {
            self.errorMessage = "Anthropic APIキーが未設定です。プロジェクト直下の .env を確認してください。"
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

                // 2. Claude API へ PDF を1ページずつ送信して翻訳（0.00→0.80）
                progressLabel = "翻訳中... (1ページ目)"
                let pairs = try await claudeService.translatePDF(
                    at: url,
                    mode: mode
                ) { [weak self] p in
                    await MainActor.run {
                        self?.progress = p * 0.80
                        // p は (完了ページ数 / 総ページ数) なので逆算してページ番号を表示
                        // 厳密な総ページ数は ClaudeService 内部のため近似表示
                        self?.progressLabel = String(format: "翻訳中... %.0f%%", p * 100)
                    }
                }
                progress = 0.80

                // 3. 画像抽出（任意）
                progressLabel = "画像を抽出中..."
                let images: [ExtractedImage] = ignoreImages ? [] :
                    (try? await imageExtractor.extractImages(from: url)) ?? []
                progress = 0.90

                // 4. PDF 生成
                progressLabel = "PDFを生成中..."
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString + ".pdf")
                try await PDFGenerator().generate(
                    originals: pairs.map(\.original),
                    translated: pairs.map(\.translation),
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
