#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
destination="${1:-/Applications/BKAppSwitch.app}"
if [[ ! -d dist/BKAppSwitch.app ]]; then
    print -u2 "请先运行 zsh scripts/build-app.sh"
    exit 1
fi
mkdir -p .build
xcrun swiftc -module-cache-path .build/icon-module-cache scripts/CheckAppNotRunning.swift -o .build/check-app-not-running
.build/check-app-not-running
codesign --verify --strict dist/BKAppSwitch.app
ditto dist/BKAppSwitch.app "$destination"
codesign --verify --strict "$destination"
print "已安装到：$destination"
print "请只授权并运行此路径。若已有旧授权，先在辅助功能列表移除旧条目，再添加此应用。"
