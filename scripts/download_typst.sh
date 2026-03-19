#!/bin/bash
# typst 0.14.2 ユニバーサルバイナリを取得して Sources/KnittingTranslator/Resources/typst に配置する
set -euo pipefail

VERSION="0.14.2"
DEST="Sources/KnittingTranslator/Resources/typst"
TMPDIR_WORK=$(mktemp -d)

cleanup() { rm -rf "$TMPDIR_WORK"; }
trap cleanup EXIT

cd "$(dirname "$0")/.."

echo "▶ typst $VERSION を取得中..."

curl -fsSL "https://github.com/typst/typst/releases/download/v${VERSION}/typst-aarch64-apple-darwin.tar.xz" \
  | tar xJ -C "$TMPDIR_WORK"
curl -fsSL "https://github.com/typst/typst/releases/download/v${VERSION}/typst-x86_64-apple-darwin.tar.xz" \
  | tar xJ -C "$TMPDIR_WORK"

echo "▶ ユニバーサルバイナリを生成中..."
lipo -create \
  "$TMPDIR_WORK/typst-aarch64-apple-darwin/typst" \
  "$TMPDIR_WORK/typst-x86_64-apple-darwin/typst" \
  -output "$DEST"

chmod +x "$DEST"
echo "✓ $DEST を配置しました"
lipo -info "$DEST"
