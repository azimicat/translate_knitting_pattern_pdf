#!/bin/bash
set -euo pipefail

# ---------------------------------------------------------------------------
# build-release.sh
# KnittingTranslator のリリース用バイナリ（.app）を生成して zip に書き出すスクリプト
#
# 使い方:
#   ./scripts/build-release.sh                   # build/ ディレクトリに出力
#   ./scripts/build-release.sh ./dist            # 任意の出力先を指定
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_DIR="${1:-$PROJECT_ROOT/build}"
APP_NAME="KnittingTranslator"
APP_PATH="$OUTPUT_DIR/$APP_NAME.app"
ZIP_PATH="$OUTPUT_DIR/$APP_NAME.zip"

echo "==> 出力先: $OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

echo "==> .app バンドルを生成"
bash "$SCRIPT_DIR/make_app.sh"

echo "==> .app を出力先に移動"
rm -rf "$APP_PATH"
ditto "$PROJECT_ROOT/$APP_NAME.app" "$APP_PATH"
rm -rf "$PROJECT_ROOT/$APP_NAME.app"

echo "==> zip に圧縮"
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

echo ""
echo "✓ 完了"
echo "  アプリ : $APP_PATH"
echo "  zip    : $ZIP_PATH"
