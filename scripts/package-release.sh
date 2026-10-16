#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"

# Build in isolation: packaging must not replace a running, authorized copy.
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
name="AppSwitch-${version}-macOS-arm64"
mkdir -p .build dist
output="$PWD/dist/${name}.dmg"
if [[ -e "$output" || -e "${output}.sha256" ]]; then
    print -u2 "发布文件已存在，请先移走后再打包：$output"
    exit 1
fi
work="$(mktemp -d "$PWD/.build/distribution.XXXXXX")"
payload="$work/payload"
app="$payload/AppSwitch.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$work/AppIcon.iconset"

triple="arm64-apple-macosx13.0"
scratch="$PWD/.build/distribution-arm64"
swift build --scratch-path "$scratch" --triple "$triple" -c release --product AppSwitch
binary_dir="$(swift build --scratch-path "$scratch" --triple "$triple" -c release --show-bin-path)"
cp "$binary_dir/AppSwitch" "$app/Contents/MacOS/AppSwitch"
if [[ "$(xcrun lipo -archs "$app/Contents/MacOS/AppSwitch")" != arm64 ]]; then
    print -u2 "架构检查失败：需要仅含 arm64 的二进制。"
    exit 1
fi
cp Resources/Info.plist "$app/Contents/Info.plist"
xcrun swiftc -module-cache-path "$PWD/.build/icon-module-cache" Resources/GenerateIcon.swift -o "$work/generate-icon"
"$work/generate-icon" "$work/AppIcon.iconset"
iconutil -c icns "$work/AppIcon.iconset" -o "$app/Contents/Resources/AppIcon.icns"
codesign --force --sign - --identifier dev.appswitch.app "$app"
codesign --verify --strict --verbose=2 "$app"
plutil -lint "$app/Contents/Info.plist"

cp Resources/Distribution/安装说明.txt "$payload/安装说明.txt"
ln -s /Applications "$payload/Applications"
hdiutil create -volname "AppSwitch ${version}" -srcfolder "$payload" -fs HFS+ -format UDZO "$output"
hdiutil verify "$output"
(cd dist && shasum -a 256 "${name}.dmg" > "${name}.dmg.sha256")
print "已生成：$output"
print "暂存目录：$work"
print "macOS 13+；仅 Apple 芯片（arm64）；临时签名，未做 Apple 公证。"
