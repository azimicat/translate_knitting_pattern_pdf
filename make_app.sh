#!/bin/bash
# KnittingTranslator.app バンドルを作成するスクリプト
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="KnittingTranslator"
ARCH=$(uname -m)
BUILD_DIR="$PROJECT_DIR/.build/${ARCH}-apple-macosx/release"
APP_BUNDLE="$PROJECT_DIR/$APP_NAME.app"

echo "=== $APP_NAME をビルド中 (release / $ARCH) ==="
cd "$PROJECT_DIR"
swift build -c release

echo ""
echo "=== .app バンドルを作成中 ==="
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# 実行ファイルをコピー
cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
echo "  実行ファイル: コピー済み"

# SPM リソースバンドルをコピー (needle_dictionary.json 等)
RESOURCE_BUNDLE="$BUILD_DIR/${APP_NAME}_${APP_NAME}.bundle"
if [ -d "$RESOURCE_BUNDLE" ]; then
    cp -r "$RESOURCE_BUNDLE" "$APP_BUNDLE/Contents/Resources/"
    echo "  リソースバンドル: コピー済み"
else
    echo "  警告: リソースバンドルが見つかりません ($RESOURCE_BUNDLE)"
fi

# .env をバンドルに埋め込む (APIキー用)
if [ -f "$PROJECT_DIR/.env" ]; then
    cp "$PROJECT_DIR/.env" "$APP_BUNDLE/Contents/Resources/.env"
    echo "  .env (APIキー): バンドルに埋め込み済み"
else
    echo "  警告: .env ファイルが見つかりません"
    echo "        プロジェクト直下に .env を作成してください:"
    echo "        GOOGLE_AI_API_KEY=your_api_key_here"
fi

# Info.plist を書き込む
cat > "$APP_BUNDLE/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>KnittingTranslator</string>
    <key>CFBundleIdentifier</key>
    <string>com.azimicat.KnittingTranslator</string>
    <key>CFBundleName</key>
    <string>KnittingTranslator</string>
    <key>CFBundleDisplayName</key>
    <string>Knitting Translator</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST
echo "  Info.plist: 作成済み"

echo ""
echo "=== コード署名 (ad-hoc) ==="
codesign --force --deep --sign - \
    --entitlements "$PROJECT_DIR/KnittingTranslator.entitlements" \
    "$APP_BUNDLE"
echo "  署名: 完了"

echo ""
echo "========================================"
echo "  完了: $APP_BUNDLE"
echo "========================================"
echo ""
echo "デスクトップにコピーするには:"
echo "  cp -r \"$APP_BUNDLE\" ~/Desktop/"
echo ""
echo "デスクトップに直接配置するには:"
echo "  $0 --desktop"
echo ""

# --desktop オプション: 自動でデスクトップにコピー
if [ "${1:-}" = "--desktop" ]; then
    DESKTOP_APP="$HOME/Desktop/$APP_NAME.app"
    rm -rf "$DESKTOP_APP"
    cp -r "$APP_BUNDLE" "$DESKTOP_APP"
    echo "デスクトップにコピーしました: $DESKTOP_APP"
fi
