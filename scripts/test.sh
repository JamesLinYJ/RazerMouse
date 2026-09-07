#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail
cd "$(dirname "$0")/.."
cargo test -p razer-core --lib
# Keep signed test bundles outside iCloud/File Provider directories.
export RAZER_SCREENSHOT_DIR="$PWD/build/screenshots"
swift test --package-path app --scratch-path "${TMPDIR:-/tmp}/razer-mouse-swift-tests"
