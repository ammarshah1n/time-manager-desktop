#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT_DIR/Assets.xcassets/AppIcon.appiconset"
TMP_MAIN="/tmp/timed_app_icon_main.swift"
BIN="/tmp/timed-app-icon-renderer"

mkdir -p "$OUT_DIR"

# Short-circuit: this renderer swiftc-compiles the whole app, which fails
# because SwiftPM deps (Supabase, ElevenLabs, MSAL, etc.) aren't resolvable
# from a bare swiftc invocation. If the iconset already has its full set of
# PNGs, skip the re-render — package_app.sh will copy them as-is.
REQUIRED_ICONS=(icon_16x16.png icon_16x16@2x.png icon_32x32.png icon_32x32@2x.png icon_128x128.png icon_128x128@2x.png icon_256x256.png icon_256x256@2x.png icon_512x512.png icon_512x512@2x.png)
ALL_PRESENT=true
for f in "${REQUIRED_ICONS[@]}"; do
  [[ -f "$OUT_DIR/$f" ]] || { ALL_PRESENT=false; break; }
done
if $ALL_PRESENT; then
  echo "[render_app_icons] all icons present — skipping re-render"
  exit 0
fi

cat >"$TMP_MAIN" <<'SWIFT'
import AppKit
import SwiftUI

private let specs: [(filename: String, size: CGFloat)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

@MainActor
private func writePNG(size: CGFloat, to path: String) throws {
    let renderer = ImageRenderer(
        content: TimedLogoMark(size: size)
            .frame(width: size, height: size)
            .preferredColorScheme(.dark)
    )
    renderer.scale = 1
    renderer.isOpaque = false

    guard let image = renderer.nsImage else {
        throw NSError(domain: "TimedAppIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not render TimedLogoMark."])
    }

    guard
        let tiff = image.tiffRepresentation,
        let rep = NSBitmapImageRep(data: tiff),
        let png = rep.representation(using: .png, properties: [:])
    else {
        throw NSError(domain: "TimedAppIcon", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not encode PNG icon output."])
    }

    try png.write(to: URL(fileURLWithPath: path), options: [.atomic])
}

@main
struct TimedAppIconRenderer {
    static func main() async throws {
        let outputDirectory = CommandLine.arguments[1]

        try await MainActor.run {
            for spec in specs {
                try writePNG(
                    size: spec.size,
                    to: outputDirectory + "/" + spec.filename
                )
            }
        }
    }
}
SWIFT

# Swift sources live in subdirectories under Sources/; a flat glob matches
# nothing and fails under `set -u pipefail`. Use find to list everything
# except Sources/Legacy (which isn't in the SwiftPM target either).
SOURCE_FILES=()
while IFS= read -r f; do SOURCE_FILES+=("$f"); done < <(find "$ROOT_DIR/Sources" -name "*.swift" -not -path "*/Legacy/*")

xcrun swiftc \
    -D SCREENSHOT_RENDERER \
    -target arm64-apple-macos15.0 \
    -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
    "${SOURCE_FILES[@]}" \
    "$TMP_MAIN" \
    -o "$BIN"

"$BIN" "$OUT_DIR"

cat >"$OUT_DIR/Contents.json" <<'JSON'
{
  "images" : [
    {
      "filename" : "icon_16x16.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "16x16"
    },
    {
      "filename" : "icon_16x16@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "16x16"
    },
    {
      "filename" : "icon_32x32.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "32x32"
    },
    {
      "filename" : "icon_32x32@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "32x32"
    },
    {
      "filename" : "icon_128x128.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "128x128"
    },
    {
      "filename" : "icon_128x128@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "128x128"
    },
    {
      "filename" : "icon_256x256.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "256x256"
    },
    {
      "filename" : "icon_256x256@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "256x256"
    },
    {
      "filename" : "icon_512x512.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "512x512"
    },
    {
      "filename" : "icon_512x512@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "512x512"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
JSON

echo "Rendered app icons into $OUT_DIR"
