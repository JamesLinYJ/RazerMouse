#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail
cd "$(dirname "$0")/.."
: "${NOTARIZED_APP:?Set NOTARIZED_APP to the notarized, stapled RazerMouse.app}"
: "${SIGN_IDENTITY:?Set SIGN_IDENTITY to a Developer ID Application identity SHA-1}"
dmg_python="${DMG_PYTHON:-python3}"
"$dmg_python" -c 'import dmgbuild' || { echo 'Install dmgbuild==1.6.5 in a local virtual environment.' >&2; exit 1; }
codesign --verify --deep --strict "$NOTARIZED_APP"
xcrun stapler validate "$NOTARIZED_APP"
dmg_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$NOTARIZED_APP/Contents/Info.plist")
dmg_stage=$(mktemp -d "${TMPDIR:-/tmp}/razermouse-dmg.XXXXXX")
trap 'rm -rf "$dmg_stage"' EXIT
swift scripts/render-dmg-background.swift "$dmg_stage" app/Sources/RazerMouse/Resources/ControlIcons.xcassets/mouse-art.imageset/mouse-art.svg "$dmg_version"
"$dmg_python" -m dmgbuild -s scripts/dmg-settings.py -D app="$NOTARIZED_APP" -D background="$dmg_stage/background.png" 'RazerMouse' "$dmg_stage/RazerMouse.dmg"
codesign --force --sign "$SIGN_IDENTITY" --timestamp "$dmg_stage/RazerMouse.dmg"
codesign --verify --strict "$dmg_stage/RazerMouse.dmg"
# A stapled app does not replace notarization of the outer disk image.
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$dmg_stage/RazerMouse.dmg" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$dmg_stage/RazerMouse.dmg"
  xcrun stapler validate "$dmg_stage/RazerMouse.dmg"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg_stage/RazerMouse.dmg"
fi
mkdir -p "build/release/v$dmg_version"
cp "$dmg_stage/RazerMouse.dmg" "build/release/v$dmg_version/RazerMouse-v$dmg_version-macos-arm64.dmg"
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  printf 'Signed, notarized and stapled DMG created.\n'
else
  printf 'Signed DMG created; notarize and staple the container before publishing.\n'
fi
