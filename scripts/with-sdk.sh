#!/bin/bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/select-sdk.sh"
select_macos_sdk
exec "$@"
