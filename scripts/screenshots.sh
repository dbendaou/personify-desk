#!/bin/bash
# Capture the main window of a demo launch. Run this on a Mac.
# PERSONIFY_DEMO=1 and --demo both skip Bluetooth and show sample rooms.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
mkdir -p docs/screenshots

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "screenshots.sh needs macOS and screencapture." >&2
  exit 1
fi

make app
open "$root/dist/PersonifyDesk.app" --args --demo

window_id=""
for _ in 1 2 3 4 5 6 7 8 9 10; do
  sleep 1
  window_id="$(swift - <<'SWIFT'
import CoreGraphics
let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
for window in info {
    let owner = window[kCGWindowOwnerName as String] as? String ?? ""
    let layer = window[kCGWindowLayer as String] as? Int ?? -1
    if owner == "PersonifyDesk" && layer == 0 {
        print(window[kCGWindowNumber as String] ?? "")
        break
    }
}
SWIFT
)"
  window_id="${window_id//$'\n'/}"
  if [[ -n "$window_id" ]]; then
    break
  fi
done

if [[ -z "$window_id" ]]; then
  echo "Could not find the Personify Desk window." >&2
  exit 1
fi

screencapture -l "$window_id" -o "$root/docs/screenshots/desk.png"
echo "Wrote docs/screenshots/desk.png"
