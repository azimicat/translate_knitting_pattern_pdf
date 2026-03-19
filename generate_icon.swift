#!/usr/bin/env swift
// KnittingTranslator アプリアイコン生成スクリプト
// 実行: swift generate_icon.swift <出力PNGパス>
import AppKit
import Foundation

let _ = NSApplication.shared  // オフスクリーン描画の初期化

let size: CGFloat = 1024
let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "/tmp/AppIcon-1024.png"

let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in

    // ── 背景: 毛糸らしいウォームパープルのグラデーション ──────────────
    let path = NSBezierPath(roundedRect: rect, xRadius: 210, yRadius: 210)
    path.addClip()

    let gradient = NSGradient(
        colors: [
            NSColor(calibratedRed: 0.55, green: 0.28, blue: 0.75, alpha: 1.0),  // 明るい紫
            NSColor(calibratedRed: 0.20, green: 0.07, blue: 0.42, alpha: 1.0),  // 深い紫
        ],
        atLocations: [0.0, 1.0],
        colorSpace: .deviceRGB
    )!
    gradient.draw(in: rect, angle: -50)

    // ── 毛糸玉 emoji ────────────────────────────────────────────────
    let fontSize: CGFloat = 680
    let font = NSFont(name: "Apple Color Emoji", size: fontSize)
             ?? NSFont.systemFont(ofSize: fontSize)
    let attrs: [NSAttributedString.Key: Any] = [.font: font]
    let yarn = NSAttributedString(string: "🧶", attributes: attrs)
    let yarnSize = yarn.size()
    yarn.draw(at: NSPoint(
        x: (size - yarnSize.width)  / 2,
        y: (size - yarnSize.height) / 2 + 12
    ))

    return true
}

guard let tiff   = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png    = bitmap.representation(using: .png, properties: [:])
else {
    fputs("Error: 画像の生成に失敗しました\n", stderr)
    exit(1)
}

do {
    try png.write(to: URL(fileURLWithPath: outputPath))
    print("  生成: \(outputPath)")
} catch {
    fputs("Error: \(error)\n", stderr)
    exit(1)
}
