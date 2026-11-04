#!/bin/bash
set -euo pipefail
if ! ldconfig -p 2>/dev/null | grep -q 'libncurses.so.6'; then
  sudo apt-get update -qq
  sudo apt-get install -y -qq libncurses6
fi
if swift --version 2>/dev/null | grep -q 'Swift version 6\.4'; then
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
swift --version
