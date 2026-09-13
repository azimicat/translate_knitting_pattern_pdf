# 翻訳用文章規範の出典

著者: k16shikano。取得日: 2026-09-13。以下の原文を変更せずResourcesに同梱しています。

- cognitive-rhythm-writing.md: https://gist.github.com/k16shikano/eb2929f13ed19c97188393d297be8432
- japanese-tech-writing.md: https://gist.github.com/k16shikano/fd287c3133457c4fd8f5601d34aa817d
- ライセンス: Unlicense。著者によるpublic gist全体への適用宣言: https://gist.github.com/k16shikano/67625f2a7d96e3bbdfae8d571a936063
- ライセンス本文: Resources/writing-skills-LICENSE.txt

SPMのリソース名の衝突を避けるため、SKILL.mdをそれぞれスキル名.mdとして保存しています。cognitive-rhythm-writing内の相対参照は、japanese-tech-writingの本文を先にプロンプトへ含めることで解決します。実行時にリンクを取得したり、ファイルをモデルに探させたりする必要はありません。

TranslationWritingSkills.swiftで翻訳向けの適用条件を付け、両スキルの本文を毎ページの翻訳リクエストに含めます。原文への忠実さ、編み物用語集、JSON出力を優先し、文章規範は日本語訳の表現に限定して適用します。追加の推敲API呼び出しはありませんが、送信トークン数は増えます。モデルの翻訳品質は単体テストでは保証できません。

更新時は原文を再確認し、以下のハッシュと取得日を更新してテストしてください。

## SHA-256

- `cognitive-rhythm-writing.md`: `65486e64f33ce2ab03c5db198b1f92e2838e71abfb1a80085d1b405340c11437`
- `japanese-tech-writing.md`: `ad350e0e6f5630fd94d8ab98a6aee194053b0096fdc944c23e271d6dfa09ee68`
