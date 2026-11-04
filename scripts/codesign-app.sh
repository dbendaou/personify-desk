#!/bin/bash
# Sign the app without creating or unlocking a keychain, so `security` never prompts.
# Ad-hoc by default. Set CODESIGN_IDENTITY to an existing identity to use that instead.
set -euo pipefail

APP="${1:?app bundle}"
BUNDLE_ID="${2:?bundle id}"

if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
  echo "Signing ${APP} as ${BUNDLE_ID} with identity ${CODESIGN_IDENTITY}."
  codesign --force --deep --sign "$CODESIGN_IDENTITY" --identifier "$BUNDLE_ID" --timestamp=none "$APP"
else
  echo "Signing ${APP} ad-hoc as ${BUNDLE_ID}."
  codesign --force --deep --sign - --identifier "$BUNDLE_ID" --timestamp=none "$APP"
fi

codesign --verify --deep --strict --verbose=2 "$APP"
codesign -d -r- "$APP"
