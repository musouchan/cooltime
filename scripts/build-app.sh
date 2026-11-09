#!/bin/bash
# Cooltime.app を build/ に作る（署名は ad-hoc）。使い方: scripts/build-app.sh [バージョン] [ビルド（コミットID）]
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/verify-service-icons.py
version="${1:-0.1.0}"
build="${2:-$version}"
swift build -c release --arch arm64 --arch x86_64
bin_dir="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
bin="$bin_dir/Cooltime"
app="build/Cooltime.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/Cooltime"
cp scripts/cooltime-statusline.sh scripts/cooltime-widget.js "$app/Contents/Resources/"
cp -R "$bin_dir/Cooltime_Cooltime.bundle" "$app/Contents/Resources/"
test -s "$app/Contents/Resources/Cooltime_Cooltime.bundle/ServiceIcons.png"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Cooltime</string>
  <key>CFBundleDisplayName</key><string>Cooltime</string>
  <key>CFBundleIdentifier</key><string>app.cooltime.menubar</string>
  <key>CFBundleExecutable</key><string>Cooltime</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$version</string>
  <key>CFBundleVersion</key><string>$build</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSRemindersFullAccessUsageDescription</key><string>制限が解ける時刻を、iPhone に知らせるために、リマインダーの「Cooltime」リストに項目を置きます。</string>
  <key>NSRemindersUsageDescription</key><string>制限が解ける時刻を、iPhone に知らせるために、リマインダーの「Cooltime」リストに項目を置きます。</string>
  <key>NSAppleEventsUsageDescription</key><string>制限が戻ったことを、自分宛ての iMessage で知らせるために、「メッセージ」を操作します。</string>
</dict></plist>
PLIST
codesign --force --deep --sign - "$app"
(cd build && ditto -c -k --keepParent Cooltime.app Cooltime.zip)
echo "作成しました: build/Cooltime.zip"
