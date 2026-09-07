#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail
cd "$(dirname "$0")/.."
export MACOSX_DEPLOYMENT_TARGET=14.0
RUSTFLAGS="${RUSTFLAGS:-} --remap-path-prefix=$HOME=/build-user" cargo build --release --lib
mkdir -p build/bindings app/Sources/RazerBindings app/Sources/RazerFFI/include
cargo run -p bindings-tool -- generate --library target/release/librazer_core.dylib --language swift --config crates/razer-core/uniffi.toml --out-dir build/bindings
cp build/bindings/RazerBindings.swift app/Sources/RazerBindings/
cp build/bindings/RazerFFI.h app/Sources/RazerFFI/include/
cp build/bindings/RazerFFI.modulemap app/Sources/RazerFFI/include/module.modulemap
swift build --package-path app -c release -Xswiftc -debug-prefix-map -Xswiftc "$HOME=/build-user"
mkdir -p build/RazerMouse.app/Contents/MacOS build/RazerMouse.app/Contents/Resources
cp app/.build/release/RazerMouse build/RazerMouse.app/Contents/MacOS/
cp app/Info.plist build/RazerMouse.app/Contents/
cp LICENSE build/RazerMouse.app/Contents/Resources/
ditto app/.build/release/RazerMouse_RazerMouse.bundle build/RazerMouse.app/Contents/Resources/RazerMouse_RazerMouse.bundle
swift scripts/render-app-icon.swift design/app-icon.svg build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o build/RazerMouse.app/Contents/Resources/AppIcon.icns
python3 scripts/sanitize-binary.py build/RazerMouse.app/Contents/MacOS/RazerMouse
xattr -cr build/RazerMouse.app
codesign --force --sign - build/RazerMouse.app
printf 'Built %s/build/RazerMouse.app\n' "$PWD"
