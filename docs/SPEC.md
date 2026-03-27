# 技術仕様・開発者ガイド

## ビルド・実行

**Swift Package Manager（ターミナル）:**

```sh
swift build
swift run
```

**Xcode:**

1. `Package.swift` を Xcode で開く
2. ターゲット `KnittingTranslator` を選択
3. **Signing & Capabilities** タブで `KnittingTranslator.entitlements` を割り当てる
4. ⌘R でビルド＆実行

> App Sandbox は無効です（Typst CLI を呼び出すために必要）。ネットワーク通信とファイルアクセスはエンタイトルメントで明示的に許可されています。

**テスト:**

```sh
bash scripts/test-unit.sh
```

32 件の単体テスト（APIKeyService / GeminiService / TranslationMode / TypstGenerator）が実行されます。

---

## .app バンドル作成

```sh
# プロジェクトフォルダ内に KnittingTranslator.app を作成
bash scripts/make_app.sh

# デスクトップに直接配置する場合
bash scripts/make_app.sh --desktop
```

初回実行時はアイコン（`AppIcon.icns`）を自動生成します。リセットしたい場合は `rm AppIcon.icns` してから再実行してください。

typst バイナリは `scripts/download_typst.sh` でダウンロードしてアプリに同梱します（CI でも自動実行）。

```sh
bash scripts/download_typst.sh
```

---

## 翻訳パイプライン

```
PDF ファイル（英語）
  │
  ├─ ページ分割（PDFKit）
  │
  ├─ [0% → 90%] GeminiService
  │    ページごとに PDF → base64 エンコード → Gemini 2.5 Flash API
  │    テキスト抽出 + 英→日翻訳 + グループ化 + フォントスタイル検出を 1 プロンプトで実行
  │    認証: ?key=<api_key>
  │    レスポンス: [{"original": "...", "translation": "..."}]
  │
  └─ [90% → 100%] TypstGenerator
       TranslationPair を .typ ソースに変換
       typst compile コマンドで A4 PDF を生成
       2 カラムテーブル（左=原文 / 右=翻訳）

  → バイリンガル PDF（2 カラム形式）
```

---

## Gemini API 仕様

| 項目 | 値 |
|------|-----|
| モデル | `gemini-2.5-flash` |
| エンドポイント | `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent` |
| 認証方式 | API キー（`?key=` クエリパラメータ） |
| タイムアウト（リクエスト） | 300 秒 |
| タイムアウト（リソース） | 1800 秒 |
| PDF 送信形式 | `inline_data` / `application/pdf` / base64 |
| Thinking モード | 無効（`thinkingBudget: 0`）|

---

## Typst 仕様

| 項目 | 値 |
|------|-----|
| バージョン | 0.14.2（アプリに同梱） |
| 用紙サイズ | A4（210 × 297mm） |
| マージン | 上下 15mm / 左右 12mm |
| フォント | Helvetica Neue（原文）/ Hiragino Sans（翻訳） |

---

## 出力 PDF 仕様

### レイアウト

各ページの翻訳ペアは **2 カラムのテーブル形式** で出力されます。

```
┌──────────────────────┬──────────────────────┐
│ Original             │ 翻訳                  │
├──────────────────────┼──────────────────────┤
│ Row 1: K2, P2, *K4, │ 1段目：表2目、裏2目、  │
│ rep from * to end.   │ *表4目を繰り返す。     │
├──────────────────────┼──────────────────────┤
│ Materials: 200g of   │ 材料：並太毛糸200g、   │
│ worsted weight yarn. │ 5mm棒針1組。           │
└──────────────────────┴──────────────────────┘
```

### グループ化の仕様

| テキストの種類 | グループ化の粒度 |
|--------------|----------------|
| パターン部分（`Row 1:`, `Round 3:` など編み方指示） | 1 文（1 指示）ごとに 1 ペア |
| パターン以外（説明文・材料・ゲージ・注意書きなど） | 段落・意味のまとまりごとに 1 ペア |

### フォントスタイル

原文 PDF の**太字**・*斜体*は出力 PDF にも反映されます（`<b>` / `<i>` タグ経由で Typst の `#strong` / `#emph` に変換）。

---

## ファイル構成

```
translate_knitting_pattern_pdf/
├── Package.swift
├── VERSION                                ← リリースバージョン番号
├── KnittingTranslator.entitlements        ← ネットワーク・ファイルアクセス権限
├── generate_icon.swift                    ← AppIcon.icns 生成ユーティリティ
├── scripts/
│   ├── make_app.sh                        ← .app バンドル作成・署名
│   ├── build-app.sh                       ← ビルド確認（CI 用）
│   ├── build-release.sh                   ← リリース zip 生成（CI 用）
│   ├── test-unit.sh                       ← ユニットテスト実行
│   └── download_typst.sh                  ← typst バイナリのダウンロード
├── docs/
│   ├── SPEC.md                            ← このファイル
│   ├── ARCHITECTURE.md                    ← アーキテクチャ詳細
│   ├── USER_MANUAL.md                     ← 操作マニュアル
│   └── Google_AI_APIキーの取得方法.md
├── Sources/KnittingTranslator/
│   ├── KnittingTranslatorApp.swift        ← @main App エントリポイント
│   ├── Views/
│   │   ├── ContentView.swift              ← メイン UI・保存ダイアログ
│   │   ├── APIKeySetupView.swift          ← APIキー入力シート
│   │   ├── DropZoneView.swift             ← PDF ドロップ＆ファイル選択
│   │   └── PDFPreviewView.swift           ← 生成 PDF のインライン表示
│   ├── Models/
│   │   ├── TranslationMode.swift          ← 棒針 / かぎ針 enum
│   │   └── AppState.swift                 ← @Observable 状態管理・パイプライン制御
│   ├── Services/
│   │   ├── APIKeyService.swift            ← APIキーの保存・読み込み（UserDefaults）
│   │   ├── APIUsageTracker.swift          ← 日次クォータ追跡
│   │   ├── GeminiService.swift            ← Gemini API クライアント
│   │   └── TypstGenerator.swift           ← バイリンガル PDF 生成
│   └── Resources/
│       ├── typst                          ← 同梱 Typst バイナリ（gitignore 済み）
│       └── help_apikey.md
└── Tests/KnittingTranslatorTests/
    ├── APIKeyServiceTests.swift
    ├── APIUsageTrackerTests.swift
    ├── GeminiServiceTests.swift
    ├── TranslationModeTests.swift
    ├── TypstBundleTests.swift
    ├── TypstGeneratorTests.swift
    └── ReadPageCountTests.swift
```
