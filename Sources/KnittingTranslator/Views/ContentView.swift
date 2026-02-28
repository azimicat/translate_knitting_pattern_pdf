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
    }

    // NSSavePanel: async begin() available on macOS 13+
    // Requires com.apple.security.files.user-selected.read-write entitlement
    @MainActor
    private func saveGeneratedPDF() {
        guard let doc = appState.generatedDocument else { return }
        Task {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.pdf]
            panel.nameFieldStringValue = "\(appState.originalFileName)_jp.pdf"
            let response = await panel.begin()
            guard response == .OK, let dest = panel.url else { return }
            doc.dataRepresentation().flatMap { try? $0.write(to: dest) }
        }
    }
}
