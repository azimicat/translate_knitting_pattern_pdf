# KnittingTranslator

英語の棒針・かぎ針編みパターン PDF を日本語に翻訳して、バイリンガル PDF として出力する macOS アプリです。

Google AI (Gemini 2.5 Flash) を使い、テキスト抽出と翻訳を 1 回の API コールで完結します。**Google AI の無料枠のみで動作します（月額料金不要）。**

---

## 機能

- PDF をドラッグ＆ドロップ、またはファイル選択で読み込み
- **棒針 / かぎ針**モードを切り替え可能
- ページ単位で Gemini に PDF を送信し、テキスト抽出と英→日翻訳を一括実行
- **パターン部分**（編み方指示）は 1 文ずつ、**パターン以外**（説明文・材料・注意書き）は段落ブロックごとに翻訳をペアにして出力
- 原文の**太字・斜体**フォントを出力 PDF にも反映
- 原文の画像を出力 PDF の末尾に保持（「画像を無視」オプションで省略可）
- 翻訳結果をアプリ内でプレビューし、任意の場所に PDF 保存

---

## 動作環境

| 項目 | 要件 |
|------|------|
| OS | macOS 14 Sonoma 以降 |
| Xcode / Swift | Swift 5.10 以降（Xcode 15 以降推奨） |
| API | Google AI API キー（無料） |

---

## セットアップ

### 1. Google AI API キーを取得する

1. [Google AI Studio](https://aistudio.google.com/app/apikey) にアクセス
2. **「Create API key」** をクリックしてキーを生成
3. 生成されたキーをコピーしておく

> 無料枠：15 RPM / 1,500 リクエスト/日 / 1,000,000 TPM（2025 年時点）

### 2. `.env` ファイルを作成する

プロジェクトのルートディレクトリに `.env` ファイルを作成し、取得したキーを記入します。

```sh
# プロジェクトルートで実行
cp .env.example .env
```

`.env` を編集：

```
GOOGLE_AI_API_KEY=AIzaSy...（取得したキーを貼り付け）
```

> `.env` は `.gitignore` に含まれており、リポジトリには含まれません。

### 3. ビルドして起動する

**Swift Package Manager（ターミナル）の場合：**

```sh
swift build
swift run
```

**Xcode の場合：**

1. `Package.swift` を Xcode で開く
2. ターゲット `KnittingTranslator` を選択
3. **Signing & Capabilities** タブで **App Sandbox** を有効化し、`KnittingTranslator.entitlements` を割り当てる
4. 以下の権限が有効になっていることを確認：
   - **Outgoing Connections (Client)** — API 通信に必要
   - **User Selected File (Read/Write)** — PDF の読み込み・保存に必要
5. ⌘R でビルド＆実行

---

## 使い方

1. アプリを起動する
2. **翻訳モード** を選択（棒針 / かぎ針）
3. 英語の編みパターン PDF をドロップゾーンにドラッグ、または「ファイルを選択」で指定
4. 必要に応じて「**画像を無視**」をオンにする
5. **「翻訳を開始」** をクリック
6. 進捗バーがページ単位で進む（0% → 80%: Gemini 翻訳 / 80% → 90%: 画像抽出 / 90% → 100%: PDF 生成）
7. 完了後、プレビューで確認
8. **「PDF を保存...」** で保存先を指定して出力

翻訳中に **「キャンセル」** をクリックすると処理を中断できます。

---

## 出力 PDF の仕様

### レイアウト

各翻訳ペアは以下の形式で出力されます。

```
【原文】
This is a knitting pattern worked in the round.

【翻訳】
これは輪編みで編むニットパターンです。
```

### グループ化の仕様

| テキストの種類 | グループ化の粒度 |
|--------------|----------------|
| パターン部分（`Row 1:`, `Round 3:` など編み方指示） | 1 文（1 指示）ごとに 1 ペア |
| パターン以外（説明文・材料・ゲージ・注意書きなど） | 段落・意味のまとまりごとに 1 ペア |

### フォントスタイル

原文 PDF の**太字**・*斜体*は出力 PDF にも反映されます。

- 英語原文：Helvetica（通常）/ Helvetica-Bold（太字）/ Helvetica-Oblique（斜体）
- 日本語翻訳：Hiragino Sans W3（通常）/ W6（太字）/ 合成斜体（斜体）

### 画像

「画像を無視」がオフの場合、原文 PDF から抽出した画像を出力 PDF 末尾に 2 列 × 3 行のグリッドで掲載します。

---

## ファイル構成

```
translate_knitting_pattern_pdf/
├── Package.swift
├── .env.example                           ← API キー設定のテンプレート
├── .env                                   ← 実際の API キー（要作成、git 管理外）
├── KnittingTranslator.entitlements        ← App Sandbox 権限設定
└── Sources/KnittingTranslator/
    ├── KnittingTranslatorApp.swift        ← @main App エントリポイント
    ├── Views/
    │   ├── ContentView.swift              ← メイン UI・保存ダイアログ
    │   ├── DropZoneView.swift             ← PDF ドロップ＆ファイル選択
    │   └── PDFPreviewView.swift           ← 生成 PDF のインライン表示
    ├── Models/
    │   ├── TranslationMode.swift          ← 棒針 / かぎ針 enum
    │   └── AppState.swift                 ← @Observable 状態管理・パイプライン制御
    └── Services/
        ├── EnvLoader.swift                ← .env パーサー
        ├── GeminiService.swift            ← Gemini API クライアント（テキスト抽出＋翻訳）
        ├── ImageExtractor.swift           ← CGPDFScanner による画像抽出
        └── PDFGenerator.swift             ← CoreText によるバイリンガル PDF 生成
```

---

## 技術仕様

### 翻訳パイプライン

```
PDF ファイル（英語）
  │
  ├─ ページ分割（PDFKit）
  │
  ├─ [0% → 80%] GeminiService
  │    ページごとに PDF → base64 エンコード → Gemini 2.5 Flash API
  │    テキスト抽出 + 英→日翻訳 + グループ化 + フォントスタイル検出を 1 プロンプトで実行
  │    レスポンス: [{"original": "...", "translation": "..."}]
  │
  ├─ [80% → 90%] ImageExtractor（「画像を無視」がオフの場合）
  │    CGPDFScanner + C コールバックで XObject 画像を抽出
  │    ヘッダー・フッター領域（上下 10%）および 80px 以下の小画像は除外
  │
  └─ [90% → 100%] PDFGenerator
       CoreText CTFramesetter でテキストを A4 ページに自動改ページ
       <b> / <i> タグを NSFontManager でフォントバリアントに変換
       画像は 2×3 グリッドで末尾ページに配置

  → バイリンガル PDF（日本語）
```

### API

| 項目 | 値 |
|------|-----|
| モデル | `gemini-2.5-flash` |
| エンドポイント | `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent` |
| タイムアウト（リクエスト） | 120 秒 |
| タイムアウト（リソース） | 1800 秒 |
| PDF 送信形式 | `inline_data` / `application/pdf` / base64 |

---

## 注意事項

- スキャン画像のみで構成された PDF（テキストレイヤーなし）は翻訳できません
- 1 回の翻訳でページ数分の API リクエストが発生します。無料枠（1,500 リクエスト/日）を超える場合はご注意ください
- 日本語フォントに真のイタリック体がないため、斜体は合成斜体で近似します
