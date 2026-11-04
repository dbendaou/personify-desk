# Select a macOS SDK that can compile SwiftUI with Command Line Tools.
# Source this file, then call select_macos_sdk. If SDKROOT is already set, it is left alone.

select_macos_sdk() {
  if [[ "$(uname -s 2>/dev/null || echo "")" != "Darwin" ]]; then
    return 0
  fi
  if [[ -n "${SDKROOT:-}" ]]; then
    echo "Using SDKROOT=$SDKROOT"
    return 0
  fi
  if ! command -v xcrun >/dev/null 2>&1 || ! command -v sw_vers >/dev/null 2>&1; then
    return 0
  fi

  local os_major default_path default_ver default_major
  os_major="$(sw_vers -productVersion | cut -d. -f1)"
  default_path="$(xcrun --show-sdk-path 2>/dev/null || true)"
  default_ver="$(xcrun --show-sdk-version 2>/dev/null || true)"
  default_major="${default_ver%%.*}"

  # A default SDK at or below the running OS is the normal Xcode case.
  # Command Line Tools can instead default to a newer SDK (27 on macOS 26)
  # whose SwiftUI macro plugin is not shipped.
  if [[ -n "$default_major" && "$default_major" != "*" && "$default_major" -le "$os_major" ]]; then
    echo "Using default macOS SDK $default_ver ($default_path)"
    return 0
  fi

  local dev_dir best_path="" best_ver=""
  dev_dir="$(xcode-select -p 2>/dev/null || true)"
  local dir sdk base ver major
  for dir in "$dev_dir/SDKs" "$dev_dir/Platforms/MacOSX.platform/Developer/SDKs"; do
    [[ -d "$dir" ]] || continue
    for sdk in "$dir"/MacOSX[0-9]*.sdk; do
      [[ -d "$sdk" ]] || continue
      base="$(basename "$sdk")"
      ver="${base#MacOSX}"
      ver="${ver%.sdk}"
      major="${ver%%.*}"
      [[ "$major" == "$os_major" ]] || continue
      if [[ -z "$best_ver" ]] || _sdk_version_less "$best_ver" "$ver"; then
        best_ver="$ver"
        best_path="$sdk"
      fi
    done
  done

  if [[ -z "$best_path" ]]; then
    echo "No macOS $os_major SDK next to the default (${default_ver:-unknown}). Leaving SDKROOT unset ($default_path)." >&2
    return 0
  fi

  local sdk_name resolved
  sdk_name="$(basename "$best_path" .sdk)"
  sdk_name="$(printf '%s' "$sdk_name" | tr '[:upper:]' '[:lower:]')"
  if resolved="$(xcrun --sdk "$sdk_name" --show-sdk-path 2>/dev/null)" && [[ -n "$resolved" ]]; then
    export SDKROOT="$resolved"
  else
    export SDKROOT="$best_path"
  fi
  echo "Default SDK ${default_ver:-unknown} is newer than macOS $os_major. Using SDKROOT=$SDKROOT"
}

# True when version $1 is strictly older than $2. Compares numeric dot components.
_sdk_version_less() {
  [[ "$1" == "$2" ]] && return 1
  local first
  first="$(printf '%s\n%s\n' "$1" "$2" | sort -t. -k1,1n -k2,2n -k3,3n | head -n 1)"
  [[ "$first" == "$1" ]]
}
