# アーキテクチャ

## プロジェクト概要

macOS 向け編み物パターン PDF 翻訳アプリ。英語の棒針・かぎ針編みパターン PDF を Google Gemini API で日本語に翻訳し、対訳 PDF を生成する。

- **ビルドシステム**: Swift Package Manager
- **プラットフォーム**: macOS 14+
- **UI フレームワーク**: SwiftUI
- **アーキテクチャ**: Observable + Actor

---

## ディレクトリ構成

```
translate_knitting_pattern_pdf/
├── Package.swift                        # SPM 設定（依存なし）
├── VERSION                              # バージョン番号（CI リリースで参照）
├── make_app.sh                          # .app バンドル生成スクリプト
├── generate_icon.swift                  # AppIcon 生成ユーティリティ
├── KnittingTranslator.entitlements      # サンドボックス無効・ネットワーク許可
│
├── Sources/KnittingTranslator/
│   ├── KnittingTranslatorApp.swift      # @main エントリーポイント
│   ├── Models/
│   │   ├── AppState.swift               # Observable 状態管理・翻訳パイプライン
│   │   └── TranslationMode.swift        # enum: .knitting / .crochet
│   ├── Services/
│   │   ├── GeminiService.swift          # Gemini API クライアント（翻訳）
│   │   ├── APIKeyService.swift          # API キー保存・取得（UserDefaults）
│   │   ├── APIUsageTracker.swift        # 日次クォータ追跡
│   │   └── TypstGenerator.swift         # Typst CLI による PDF 生成
│   ├── Views/
│   │   ├── ContentView.swift            # メイン UI レイアウト
│   │   ├── DropZoneView.swift           # PDF ドロップ＆ファイル選択
│   │   ├── APIKeySetupView.swift        # API キー入力シート
│   │   ├── APIKeyHelpView.swift         # API キー取得ガイド
│   │   └── PDFPreviewView.swift         # 生成 PDF プレビュー
│   └── Resources/
│       ├── typst                        # 組み込み Typst バイナリ（universal、gitignore 済み）
│       └── help_apikey.md               # バンドル内ヘルプテキスト
│
├── Tests/KnittingTranslatorTests/
│   ├── GeminiServiceTests.swift         # レスポンスパーサーテスト
│   ├── TypstGeneratorTests.swift        # マークアップ変換テスト
│   ├── APIKeyServiceTests.swift         # UserDefaults テスト
│   ├── APIUsageTrackerTests.swift       # クォータロジックテスト
│   ├── TranslationModeTests.swift       # enum テスト
│   ├── TypstBundleTests.swift           # バンドルリソース検証テスト
│   └── ReadPageCountTests.swift         # PDF ページ数カウントテスト
│
├── docs/
│   ├── ARCHITECTURE.md                  # このファイル
│   ├── USER_MANUAL.md                   # エンドユーザー向けマニュアル
│   └── Google_AI_APIキーの取得方法.md    # API キー取得手順
│
└── scripts/
    ├── build-app.sh                     # ビルド確認
    ├── build-release.sh                 # リリース用 .app と zip を生成
    ├── test-unit.sh                     # ユニットテスト実行
    └── download_typst.sh                # Typst universal バイナリをダウンロード
```

---

## レイヤー構成

```
Views
  └── ContentView / DropZoneView / PDFPreviewView
        │ @State appState
        ▼
AppState（@Observable）
  ├── processTranslation() ── GeminiService（actor）
  │                               └── Gemini 2.5 Flash API
  └── TypstGenerator（actor）
          └── typst バイナリ（bundle 同梱）
```

---

## モデル

### TranslationPair
Gemini が返す 1 行分のデータ。

```swift
struct TranslationPair {
    let original: String     // 原文
    let translated: String   // 日本語訳
    let pageNumber: Int      // 元ページ番号
}
```

### TranslationMode
```swift
enum TranslationMode: String, CaseIterable {
    case knitting = "棒針"
    case crochet  = "かぎ針"
}
```

---

## サービス

### GeminiService（actor）
- エンドポイント: `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent`
- PDF を 1 ページずつ base64 エンコードして送信
- タイムアウト: リクエスト 300 秒、リソース 1800 秒
- プロンプトに編み物・かぎ針用語集を埋め込み、翻訳精度を向上
- レスポンスからタグ付きテキストを抽出: `<b>`, `<i>`, `<u>`, `<h>`

### TypstGenerator（actor）
- bundle 内の `typst` バイナリを使用（フォールバック: `/opt/homebrew/bin/typst`）
- A4 / 2 カラム（原文 | 翻訳）の対訳 PDF を生成
- フォント: Helvetica Neue（英語）、Hiragino Sans（日本語）
- HTML タグ → Typst マークアップに変換

### APIKeyService（@Observable）
- `UserDefaults["google_ai_api_key"]` に API キーを保存
- テスト可能設計（`UserDefaults` インスタンスをインジェクト可能）

### APIUsageTracker
- 無料枠: 500 リクエスト/日
- 90% 超過時に警告アラートを表示
- 日付変更（UTC 深夜）で自動リセット

---

## データフロー

```
1. PDF をドロップ or ファイル選択
2. AppState.processTranslation() 開始
3. PDFKit で 1 ページずつ分割
4. GeminiService が各ページを Gemini に送信（進捗 0〜90%）
5. レスポンスを TranslationPair 配列に変換
6. TypstGenerator が .typ ファイルを生成し typst compile を実行（進捗 90〜100%）
7. 生成された PDF を PDFPreviewView に表示
8. ユーザーが「PDFを保存...」で書き出し
```

---

## scripts/ 一覧

| スクリプト | 用途 |
|---|---|
| `build-app.sh` | `swift build` を実行してビルドが通るか確認 |
| `build-release.sh` | `make_app.sh` を呼び出し、.app を zip 化してリリース成果物を生成 |
| `test-unit.sh` | `swift test` を実行してユニットテストを確認 |
| `download_typst.sh` | Typst v0.14.2 の universal バイナリをダウンロードして `Resources/typst` に配置 |
| `make_app.sh` | release ビルド → .app バンドル構築 → ad-hoc 署名 |
| `generate_icon.swift` | AppIcon.icns を生成するユーティリティ |

---

## 備考

### App Sandbox が無効な理由
Typst CLI を subprocess として起動するため、App Sandbox を無効にしている。

### Typst バイナリが gitignore される理由
83.5 MB あるため git 管理対象外。`scripts/download_typst.sh` で取得する。CI でも同スクリプトを実行する。

### バージョン管理
`VERSION` ファイルにセマンティックバージョン（例: `1.0.0`）を記載。`release.yml` がここを参照してタグを生成する。
