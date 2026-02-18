#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_PATH="${1:-$ROOT_DIR/Resources/AppIcon.icns}"
WORK_DIR="$(mktemp -d)"
ICONSET_DIR="$WORK_DIR/AppIcon.iconset"
MASTER_PNG="$WORK_DIR/master.png"

mkdir -p "$(dirname "$OUTPUT_PATH")"
mkdir -p "$ICONSET_DIR"

cat > "$WORK_DIR/generate_icon.swift" <<'SWIFT'
import AppKit
import Foundation

let outPath = CommandLine.arguments[1]
let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))

image.lockFocus()
guard let ctx = NSGraphicsContext.current?.cgContext else {
    fatalError("Не удалось получить графический контекст")
}

let rect = CGRect(x: 0, y: 0, width: size, height: size)
let space = CGColorSpaceCreateDeviceRGB()
let gradient = CGGradient(
    colorsSpace: space,
    colors: [NSColor(calibratedRed: 0.09, green: 0.36, blue: 0.86, alpha: 1.0).cgColor,
             NSColor(calibratedRed: 0.02, green: 0.12, blue: 0.45, alpha: 1.0).cgColor] as CFArray,
    locations: [0.0, 1.0]
)!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])

let glow = NSBezierPath(ovalIn: CGRect(x: size * 0.58, y: size * 0.50, width: size * 0.5, height: size * 0.5))
NSColor(calibratedRed: 0.45, green: 0.9, blue: 1.0, alpha: 0.25).setFill()
glow.fill()

let attrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 460, weight: .heavy),
    .foregroundColor: NSColor.white
]
let text = "AI" as NSString
let textRect = CGRect(x: 170, y: 230, width: 700, height: 560)
text.draw(in: textRect, withAttributes: attrs)

image.unlockFocus()

guard
    let tiff = image.tiffRepresentation,
    let rep = NSBitmapImageRep(data: tiff),
    let png = rep.representation(using: .png, properties: [:])
else {
    fatalError("Не удалось сгенерировать PNG")
}

try png.write(to: URL(fileURLWithPath: outPath))
SWIFT

swift "$WORK_DIR/generate_icon.swift" "$MASTER_PNG"

sips -z 16 16 "$MASTER_PNG" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
sips -z 32 32 "$MASTER_PNG" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$MASTER_PNG" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
sips -z 64 64 "$MASTER_PNG" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$MASTER_PNG" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
sips -z 256 256 "$MASTER_PNG" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$MASTER_PNG" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
sips -z 512 512 "$MASTER_PNG" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$MASTER_PNG" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$MASTER_PNG" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null

iconutil -c icns "$ICONSET_DIR" -o "$OUTPUT_PATH"
rm -rf "$WORK_DIR"

echo "Готово: $OUTPUT_PATH"
