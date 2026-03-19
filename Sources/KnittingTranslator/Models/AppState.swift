import PDFKit
import SwiftUI

/// アプリ全体の状態管理とパイプライン制御を担う。
/// パイプライン: GeminiService（翻訳） → TypstGenerator（PDF生成）
@MainActor
@Observable
final class AppState {

    // MARK: - Published state

    var mode: TranslationMode = .knitting
    var droppedURL: URL?       = nil
    var originalFileName: String = ""
    var errorMessage: String?  = nil
    var isProcessing: Bool     = false
    var progress: Double       = 0
    var progressLabel: String  = ""
    var generatedDocument: PDFDocument? = nil

    /// true のとき APIKeySetupView シートを表示する
    var showAPIKeySetup: Bool = false

    // MARK: - Services

    let apiKeyService = APIKeyService()
    private let geminiService = GeminiService()
    private var translationTask: Task<Void, Never>?

    // MARK: - Init

    init() {
        // APIキー未設定なら起動時に設定シートを表示
        showAPIKeySetup = !apiKeyService.hasKey
    }

    // MARK: - API Key

    func saveAPIKey(_ key: String) {
        apiKeyService.save(key)
        showAPIKeySetup = false
        errorMessage = nil
    }

    // MARK: - Translation

    func processTranslation() async {
        guard let url = droppedURL else { return }
        guard let apiKey = apiKeyService.apiKey() else {
            showAPIKeySetup = true
            return
        }
        let mode = self.mode

        isProcessing = true
        progress     = 0
        errorMessage = nil

        translationTask = Task { [weak self] in
            guard let self else { return }
            do {
                // security-scoped resource はファイルピッカー / ドロップで取得した URL に必要
                guard url.startAccessingSecurityScopedResource() else {
                    throw AppError.fileAccessDenied
                }
                defer { url.stopAccessingSecurityScopedResource() }

                // 1. Gemini で翻訳（0% → 90%）
                progressLabel = "Gemini で翻訳中..."
                let pairs = try await geminiService.translatePDF(
                    at: url,
                    mode: mode,
                    apiKey: apiKey
                ) { [weak self] p in
                    await MainActor.run {
                        self?.progress     = p * 0.90
                        self?.progressLabel = String(format: "Gemini で翻訳中... %.0f%%", p * 100)
                    }
                }
                progress = 0.90

                // 2. Typst で PDF 生成（90% → 100%）
                progressLabel = "PDFを生成中..."
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString + ".pdf")
                try await TypstGenerator().generate(pairs: pairs, to: tempURL)

                generatedDocument = PDFDocument(url: tempURL)
                progress      = 1.0
                progressLabel = "完了"

            } catch {
                if !(error is CancellationError) {
                    errorMessage = error.localizedDescription
                }
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

// MARK: - AppError

enum AppError: LocalizedError {
    case fileAccessDenied

    var errorDescription: String? {
        switch self {
        case .fileAccessDenied: return "ファイルへのアクセス権限がありません"
        }
    }
}
