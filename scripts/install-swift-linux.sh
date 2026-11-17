#!/bin/bash
set -euo pipefail

# Each Actions step starts with a clean environment. Record the directory
# that provides `swift` so later steps can call it. A runner that already
# has Swift 6.4 returns before swiftly creates env.sh.
persist_swift_path() {
  if [[ -z "${GITHUB_PATH:-}" ]]; then
    return 0
  fi
  local swift_bin
  swift_bin="$(command -v swift)"
  dirname "$swift_bin" >> "$GITHUB_PATH"
}

if ! ldconfig -p 2>/dev/null | grep -q 'libncurses.so.6'; then
  sudo apt-get update -qq
  sudo apt-get install -y -qq libncurses6
fi
if swift --version 2>/dev/null | grep -q 'Swift version 6\.4'; then
  persist_swift_path
  swift --version
  exit 0
fi
if [[ ! -x "${HOME}/.local/share/swiftly/bin/swiftly" ]]; then
  curl -fL -o /tmp/swiftly.tar.gz "https://download.swift.org/swiftly/linux/swiftly-$(uname -m).tar.gz"
  tar -C /tmp -zxf /tmp/swiftly.tar.gz
  /tmp/swiftly init --quiet-shell-followup --assume-yes --skip-install
fi
# shellcheck disable=SC1091
. "${HOME}/.local/share/swiftly/env.sh"
swiftly install 6.4.1
swift --version | grep -q 'Swift version 6\.4'
persist_swift_path
swift --version
