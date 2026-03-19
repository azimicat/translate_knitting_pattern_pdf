import SwiftUI

struct APIKeySetupView: View {
    let existingKey: String?
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var apiKey: String = ""
    @State private var isEditing: Bool = false
    @State private var showHelp: Bool = false

    private var hasExistingKey: Bool { existingKey != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {

            VStack(alignment: .leading, spacing: 6) {
                Text(hasExistingKey ? "APIキーを変更" : "Google AI APIキーを設定")
                    .font(.title2).bold()
                Text("翻訳にはGoogle AI StudioのAPIキーが必要です。取得は無料で1分ほどで完了します。")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Link("→ AI Studioでキーを取得する（無料）",
                         destination: URL(string: "https://aistudio.google.com/app/apikey")!)
                        .font(.callout)

                    Button("取得方法を見る") { showHelp = true }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }

                Text("無料枠: 15リクエスト/分・500リクエスト/日")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("APIキー").font(.caption).foregroundStyle(.secondary)

                if hasExistingKey && !isEditing {
                    // 設定済み: マスク表示 + 変更ボタン
                    HStack {
                        Text(maskedKey(existingKey!))
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.primary)
                        Spacer()
                        Button("変更") { isEditing = true }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                    .padding(6)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                } else {
                    // 未設定 or 変更中: 入力フィールド
                    SecureField("AIzaSy...", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                        .onAppear {
                            // 変更モードでは既存キーを初期値に
                            if isEditing, let key = existingKey {
                                apiKey = key
                            }
                        }
                }
            }

            HStack {
                Button("キャンセル") {
                    if hasExistingKey && isEditing {
                        isEditing = false
                        apiKey = ""
                    } else {
                        dismiss()
                    }
                }
                .buttonStyle(.bordered)
                Spacer()
                if !hasExistingKey || isEditing {
                    Button("保存") {
                        onSave(apiKey.trimmingCharacters(in: .whitespaces))
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty)
                } else {
                    Button("閉じる") { dismiss() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(28)
        .frame(width: 420)
        .sheet(isPresented: $showHelp) {
            APIKeyHelpView()
        }
    }

    // 先頭8文字 + **** + 末尾4文字 で表示
    private func maskedKey(_ key: String) -> String {
        guard key.count > 12 else { return String(repeating: "•", count: key.count) }
        let prefix = String(key.prefix(8))
        let suffix = String(key.suffix(4))
        return "\(prefix)••••••••••••\(suffix)"
    }
}
