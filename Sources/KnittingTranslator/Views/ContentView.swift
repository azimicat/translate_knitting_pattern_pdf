import SwiftUI
import AppKit

struct ContentView: View {
    @Environment(AppState.self) var appState

    var body: some View {
        @Bindable var appState = appState
        VStack(alignment: .leading, spacing: 0) {

            // ── コントロール領域 ──────────────────────────────
            VStack(alignment: .leading, spacing: 16) {
                DropZoneView(
                    droppedURL: $appState.droppedURL,
                    errorMessage: $appState.errorMessage,
                    originalFileName: $appState.originalFileName
                )

                GroupBox("翻訳設定") {
                    Picker("翻訳モード", selection: $appState.mode) {
                        ForEach(TranslationMode.allCases) {
                            Text($0.rawValue).tag($0)
                        }
                    }
                    .pickerStyle(.radioGroup)
                }

                HStack {
                    Button("翻訳を開始") {
                        Task { await appState.processTranslation() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(appState.droppedURL == nil || appState.isProcessing)

                    if appState.isProcessing {
                        Button("キャンセル") { appState.cancelTranslation() }
                            .buttonStyle(.bordered)
                    }

                    Spacer()

                    Button {
                        appState.showAPIKeySetup = true
                    } label: {
                        Image(systemName: "key")
                    }
                    .buttonStyle(.bordered)
                    .help("APIキーを変更")
                }

                if appState.isProcessing {
                    ProgressView(value: appState.progress) {
                        Text(appState.progressLabel).font(.caption)
                    }
                }
            }
            .padding()

            // ── プレビュー＋保存ボタン（翻訳完了後に表示）────────
            if let doc = appState.generatedDocument {
                Divider()

                PDFPreviewView(document: doc)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                HStack {
                    Spacer()
                    Button("PDFを保存...") { saveGeneratedPDF() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .padding()
                }
                .background(.windowBackground)
            }
        }
        .sheet(isPresented: Binding(
            get: { appState.showAPIKeySetup },
            set: { appState.showAPIKeySetup = $0 }
        )) {
            APIKeySetupView(existingKey: appState.apiKeyService.apiKey()) { key in
                appState.saveAPIKey(key)
            }
        }
        .alert("APIリクエスト数が多くなります", isPresented: Binding(
            get: { appState.showFreeierWarningAlert },
            set: { appState.showFreeierWarningAlert = $0 }
        )) {
            Button("キャンセル", role: .cancel) {}
            Button("翻訳を開始") {
                Task { await appState.confirmAndStartTranslation() }
            }
        } message: {
            let remaining = appState.usageTracker.freeierLimit
                - appState.usageTracker.usedToday
                - appState.pageCount
            Text("""
            このPDFは\(appState.pageCount)ページあります。
            \(appState.pageCount)回のAPIリクエストが発生します。

            本日の使用量: \(appState.usageTracker.usedToday) / \(appState.usageTracker.freeierLimit) 回
            翻訳後の残り: \(max(0, remaining)) 回
            """)
        }
    }

    @MainActor
    private func saveGeneratedPDF() {
        guard let doc = appState.generatedDocument else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "\(appState.originalFileName)_jp.pdf"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        doc.dataRepresentation().flatMap { try? $0.write(to: dest) }
    }
}
