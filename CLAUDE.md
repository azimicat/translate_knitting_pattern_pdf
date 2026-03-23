# Claude 作業ガイド

## セッション開始時

`docs/ARCHITECTURE.md` を読んで実装全体を把握すること。

---

## コミット

コミット前に必ずビルドとテストを通過させること。

```bash
git add <変更ファイル>
git commit
```

---

## ビルド確認

コード変更後は必ず通ることを確認すること。`Build complete!` 以外が出たらエラーを修正してから次へ進む。

```bash
bash scripts/build-app.sh
```

---

## テスト

仕様が確定したらテストを実装し、通過を確認すること。

```bash
bash scripts/test-unit.sh   # ユニットテスト（32 件）
```

---

## typst バイナリについて

`Sources/KnittingTranslator/Resources/typst` は gitignore 済みのため、初回セットアップ時にダウンロードすること。

```bash
bash scripts/download_typst.sh
```

CI でも同スクリプトを実行している。

---

## 作業完了後

以下を必ず更新すること。

### docs/ARCHITECTURE.md

実装の追加・変更があれば更新する。

### docs/USER_MANUAL.md

以下のいずれかに該当する変更を行った場合は必ず更新する。

- 操作方法が変わった
- UI の構成が変わった（ツールバー・ドロップゾーン・プレビューなど）
- 機能が追加・削除された
- 仕様が変わった（クォータ上限・保存挙動・出力フォーマットなど）

`docs/USER_MANUAL.md` はエンジニア以外のユーザーが読む文書のため、実装の詳細ではなく「何ができるか・どう操作するか」を簡潔に書くこと。
