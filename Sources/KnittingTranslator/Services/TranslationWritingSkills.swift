import Foundation

/// 同梱した文章規範を、原文に忠実な翻訳の補助としてGeminiへ渡す。
enum TranslationWritingSkills {
    static func instructions(bundle: Bundle = .module) throws -> String {
        let names = ["japanese-tech-writing", "cognitive-rhythm-writing"]
        let skills = try names.map { name -> String in
            guard let url = bundle.url(forResource: name, withExtension: "md"),
                  let text = try? String(contentsOf: url, encoding: .utf8),
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw GeminiError.writingSkillLoadFailed
            }
            return "【\(name) 原文】\n\(text)"
        }.joined(separator: "\n\n")

        return """
        【文章規範を翻訳に適用する際の最優先条件】
        この作業は編み物パターンの忠実な翻訳であり、新しい記事の執筆ではない。
        以下の文章規範はtranslationの日本語表現にだけ適用し、originalは書き換えない。
        文章規範と競合する場合は、この適用条件、翻訳タスクの用語集・書式・JSON出力指定を優先する。
        - 目数・段数・サイズ別の数値・単位・反復回数・記号・左右・表裏・条件・手順の順序を保持する。
        - 原文の情報や必要な反復を、冗長さの削減や短文化を理由に省略しない。
        - 原文にない問いかけ・逡巡・感情・具体例・理由・結論・予告を創作しない。断定と推量、禁止と推奨の強さを変えない。
        - 編み方の指示、材料、ゲージ、注意事項は正確で直接的に訳す。リズムのために情報を後回しにしない。
        - 説明文では意味のまとまりを保ち、日本語として自然な語順・文の長さ・接続を選ぶ。段落やページをまたいで内容を移動しない。
        - 原文の見出しや太字・斜体・下線は翻訳タスクの指定どおり保持する。
        - 点検は内部で行い、規範の説明・点検結果・例文を翻訳結果に混ぜない。
        参照先のjapanese-tech-writingを先に、cognitive-rhythm-writingを次に全文掲載する。
        規範内の相対パスは以下の本文で解決済みであり、外部ファイルの取得は不要。

        \(skills)

        【文章規範の終わり・翻訳条件の再確認】
        原文の意味・数値・条件・順序を保持し、創作・省略をしない。
        説明文の読みやすさを整え、編む指示は正確に訳す。出力は指定のJSON配列のみ。
        """
    }
}
