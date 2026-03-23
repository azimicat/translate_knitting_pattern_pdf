#!/bin/bash
# KnittingTranslator.app バンドルを作成するスクリプト
set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="KnittingTranslator"
ARCH=$(uname -m)
BUILD_DIR="$PROJECT_DIR/.build/${ARCH}-apple-macosx/release"
APP_BUNDLE="$PROJECT_DIR/$APP_NAME.app"
ICNS="$PROJECT_DIR/AppIcon.icns"

# ── アイコン生成 ────────────────────────────────────────────────────
# AppIcon.icns がなければ生成する
if [ ! -f "$ICNS" ]; then
    echo "=== アイコンを生成中 ==="
    ICON_BUILD="$PROJECT_DIR/.icon_build"
    ICONSET="$ICON_BUILD/AppIcon.iconset"
    BASE="$ICON_BUILD/base_1024.png"
    mkdir -p "$ICONSET"

    swift "$PROJECT_DIR/generate_icon.swift" "$BASE"

    # sips で各サイズにリサイズ
    sips -z 16   16   "$BASE" --out "$ICONSET/icon_16x16.png"      >/dev/null
    sips -z 32   32   "$BASE" --out "$ICONSET/icon_16x16@2x.png"   >/dev/null
    sips -z 32   32   "$BASE" --out "$ICONSET/icon_32x32.png"      >/dev/null
    sips -z 64   64   "$BASE" --out "$ICONSET/icon_32x32@2x.png"   >/dev/null
    sips -z 128  128  "$BASE" --out "$ICONSET/icon_128x128.png"    >/dev/null
    sips -z 256  256  "$BASE" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
    sips -z 256  256  "$BASE" --out "$ICONSET/icon_256x256.png"    >/dev/null
    sips -z 512  512  "$BASE" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
    sips -z 512  512  "$BASE" --out "$ICONSET/icon_512x512.png"    >/dev/null
    cp "$BASE"                     "$ICONSET/icon_512x512@2x.png"

    iconutil -c icns "$ICONSET" -o "$ICNS"
    rm -rf "$ICON_BUILD"
    echo "  AppIcon.icns: 生成完了"
    echo ""
fi

# ── ビルド ──────────────────────────────────────────────────────────
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

# アイコンをコピー
cp "$ICNS" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
echo "  AppIcon.icns: コピー済み"

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
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
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
