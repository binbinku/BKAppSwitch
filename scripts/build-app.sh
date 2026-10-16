#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"

configuration="${CONFIGURATION:-release}"
mkdir -p .build
xcrun swiftc -module-cache-path .build/icon-module-cache scripts/CheckAppNotRunning.swift -o .build/check-app-not-running
.build/check-app-not-running
swift build -c "$configuration"
binary_dir="$(swift build -c "$configuration" --show-bin-path)"
app="$PWD/dist/AppSwitch.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" .build/AppIcon.iconset
xcrun swiftc -module-cache-path .build/icon-module-cache Resources/GenerateIcon.swift -o .build/generate-icon
.build/generate-icon .build/AppIcon.iconset
cp "$binary_dir/AppSwitch" "$app/Contents/MacOS/AppSwitch"
cp Resources/Info.plist "$app/Contents/Info.plist"
iconutil -c icns .build/AppIcon.iconset -o "$app/Contents/Resources/AppIcon.icns"
codesign --force --sign "${APPSWITCH_SIGN_IDENTITY:--}" --identifier dev.appswitch.app "$app"
codesign --verify --strict "$app"
print "已生成：$app"
if [[ "${APPSWITCH_SIGN_IDENTITY:--}" == "-" ]]; then
    print "本地临时签名：如本次二进制有改动，须移除旧辅助功能条目并重新添加此版本。"
fi
