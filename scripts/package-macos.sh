#!/usr/bin/env bash
# Packs Glossplay.app and a .dmg on macOS. Run on a Mac (or the macos CI runner) after
#   brew install mpv ffmpeg dylibbundler create-dmg
#   cargo build --release --locked -p glossplay
# Usage: scripts/package-macos.sh [path/to/glossplay]   -> dist/Glossplay-<version>-macos-<arch>.dmg
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
exe="${1:-$repo/target/release/glossplay}"
[ -f "$exe" ] || { echo "Binary not found: $exe (cargo build --release -p glossplay)" >&2; exit 1; }
for t in dylibbundler create-dmg iconutil sips; do
  command -v "$t" >/dev/null || { echo "Missing tool: $t" >&2; exit 1; }
done

version="$(sed -n 's/^version = "\(.*\)"/\1/p' "$repo/Cargo.toml" | head -1)"
arch="$(uname -m)"
brew_prefix="$(brew --prefix)"
libmpv="$brew_prefix/lib/libmpv.2.dylib"
[ -f "$libmpv" ] || libmpv="$(readlink -f "$brew_prefix/lib/libmpv.dylib")"
ffmpeg="$(command -v ffmpeg)"

out="$repo/dist"
app="$out/Glossplay.app"
rm -rf "$app" "$out"/*.dmg
mkdir -p "$app/Contents/MacOS" "$app/Contents/Frameworks" "$app/Contents/Resources"

# The player looks for libmpv.2.dylib and ffmpeg next to its executable.
cp "$exe" "$app/Contents/MacOS/glossplay"
cp "$libmpv" "$app/Contents/MacOS/libmpv.2.dylib"
cp "$ffmpeg" "$app/Contents/MacOS/ffmpeg"
chmod u+w "$app/Contents/MacOS/"*

# Copy every Homebrew library they depend on into Frameworks and rewrite the load paths.
dylibbundler -of -b -cd \
  -x "$app/Contents/MacOS/libmpv.2.dylib" \
  -x "$app/Contents/MacOS/ffmpeg" \
  -d "$app/Contents/Frameworks" -p "@executable_path/../Frameworks/"

# Icon: .icns from the 512 px PNG.
iconset="$(mktemp -d)/icon.iconset"
mkdir -p "$iconset"
src="$repo/assets/icon-512.png"
for s in 16 32 128 256 512; do
  sips -z $s $s "$src" --out "$iconset/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$src" --out "$iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$app/Contents/Resources/icon.icns"

cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Glossplay</string>
  <key>CFBundleDisplayName</key><string>Glossplay</string>
  <key>CFBundleIdentifier</key><string>app.glossplay.player</string>
  <key>CFBundleExecutable</key><string>glossplay</string>
  <key>CFBundleIconFile</key><string>icon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$version</string>
  <key>CFBundleVersion</key><string>$version</string>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.video</string>
  <key>CFBundleDocumentTypes</key><array><dict>
    <key>CFBundleTypeName</key><string>Video</string>
    <key>CFBundleTypeRole</key><string>Viewer</string>
    <key>LSItemContentTypes</key><array><string>public.movie</string></array>
  </dict></array>
</dict></plist>
PLIST

mkdir -p "$app/Contents/Resources/licenses"
cp "$repo/LICENSE" "$repo/THIRD-PARTY.txt" "$repo/THIRD-PARTY-RUST.txt" "$app/Contents/Resources/licenses/"

# Ad-hoc signature (no Apple Developer account): Apple Silicon refuses unsigned code.
# For distribution without the right-click "Open" step, sign with a Developer ID and notarize.
codesign --force --deep --sign - "$app"

dmg="$out/Glossplay-$version-macos-$arch.dmg"
create-dmg --volname "Glossplay" --window-size 540 360 --icon-size 96 \
  --icon "Glossplay.app" 130 170 --app-drop-link 410 170 --no-internet-enable \
  "$dmg" "$app"
echo "Done: $dmg"
