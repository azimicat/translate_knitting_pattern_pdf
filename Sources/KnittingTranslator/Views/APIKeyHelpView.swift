import SwiftUI

struct APIKeyHelpView: View {
    @Environment(\.dismiss) private var dismiss

    private var helpText: AttributedString {
        guard
            let url = Bundle.module.url(forResource: "help_apikey", withExtension: "md"),
            let raw = try? String(contentsOf: url, encoding: .utf8),
            let attributed = try? AttributedString(markdown: raw,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
        else {
            return AttributedString("ヘルプを読み込めませんでした。")
        }
        return attributed
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                Text(helpText)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(24)
            }

            Divider()

            HStack {
                Link("Google AI Studio を開く",
                     destination: URL(string: "https://aistudio.google.com/app/apikey")!)
                    .font(.callout)
                Spacer()
                Button("閉じる") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(width: 520, height: 600)
    }
}
