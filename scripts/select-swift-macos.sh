#!/bin/bash
# Pick a Swift 6.4 toolchain. GitHub macOS runners may still default to an
# older Xcode, so this installs the official 6.4.1 toolchain when needed.
set -euo pipefail

has_64() { "$1" --version 2>/dev/null | grep -q 'Swift version 6\.4'; }

if has_64 swift; then
  swift --version
  exit 0
fi

shopt -s nullglob
for app in /Applications/Xcode*.app; do
  bin="${app}/Contents/Developer/usr/bin/swift"
  if [[ -x "$bin" ]] && has_64 "$bin"; then
    sudo xcode-select -s "${app}/Contents/Developer"
    swift --version
    exit 0
  fi
done

curl -fL -o /tmp/swift-6.4.1.pkg \
  "https://download.swift.org/swift-6.4.1-release/xcode/swift-6.4.1-RELEASE/swift-6.4.1-RELEASE-osx.pkg"
sudo installer -pkg /tmp/swift-6.4.1.pkg -target /
toolchain="$(find /Library/Developer/Toolchains -maxdepth 1 -type d -name 'swift-6.4.1*.xctoolchain' | head -n 1)"
if [[ -z "$toolchain" ]]; then
  echo "Swift 6.4.1 toolchain was not installed" >&2
  exit 1
fi
identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${toolchain}/Info.plist")"
if [[ -n "${GITHUB_PATH:-}" ]]; then
  echo "${toolchain}/usr/bin" >> "$GITHUB_PATH"
fi
if [[ -n "${GITHUB_ENV:-}" ]]; then
  echo "TOOLCHAINS=${identifier}" >> "$GITHUB_ENV"
fi
export PATH="${toolchain}/usr/bin:${PATH}"
export TOOLCHAINS="${identifier}"
swift --version | grep -q 'Swift version 6\.4'
swift --version
