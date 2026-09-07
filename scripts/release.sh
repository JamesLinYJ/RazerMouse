#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail
cd "$(dirname "$0")/.."
: "${SIGN_IDENTITY:?Set SIGN_IDENTITY to the SHA-1 of a Developer ID Application identity}"
[ -z "$(git status --porcelain)" ] || { echo 'Commit source changes before creating a release.' >&2; exit 1; }
./scripts/build.sh
[ -z "$(git status --porcelain)" ] || { echo 'Build changed tracked files; review and commit them first.' >&2; exit 1; }
release_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' app/Info.plist)
release_revision=$(git rev-parse HEAD)
release_output="$PWD/build/release/v$release_version"
release_stage=$(mktemp -d "${TMPDIR:-/tmp}/razermouse-release.XXXXXX")
trap 'rm -rf "$release_stage"' EXIT
mkdir -p "$release_output"
release_app="$release_stage/RazerMouse.app"
ditto --noextattr --norsrc --noqtn build/RazerMouse.app "$release_app"
cp THIRD_PARTY_NOTICES.md "$release_app/Contents/Resources/"
cp docs/LICENSING.md "$release_app/Contents/Resources/PROVENANCE.md"
# Include dependency license texts without copying build paths or private key material.
cargo metadata --locked --format-version 1 > "$release_stage/dependencies.json"
python3 - "$release_stage/dependencies.json" "$release_app" <<'PY'
import json, shutil, sys
from pathlib import Path
metadata = json.loads(Path(sys.argv[1]).read_text())
target = Path(sys.argv[2]) / 'Contents/Resources/ThirdPartyLicenses'
for package in metadata['packages']:
    if not package['source']:
        continue
    root = Path(package['manifest_path']).parent
    for item in root.rglob('*'):
        if not item.is_file() or not item.name.upper().startswith(('LICENSE', 'COPYING', 'NOTICE')):
            continue
        output = target / (package['name'] + '-' + package['version']) / item.relative_to(root)
        output.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(item, output)
PY
xattr -cr "$release_app"
codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp "$release_app"
codesign --verify --deep --strict --verbose=2 "$release_app"
codesign --display --verbose=4 "$release_app" 2> "$release_stage/signature.txt"
# Refuse development or ad-hoc identities even when codesign itself succeeds.
grep -q '^Authority=Developer ID Application:' "$release_stage/signature.txt"
grep -q '^Timestamp=' "$release_stage/signature.txt"
grep -q 'flags=.*runtime' "$release_stage/signature.txt"
release_archive="$release_output/RazerMouse-v$release_version-macos-arm64.zip"
release_notarized=false
if [ -n "${NOTARY_PROFILE:-}" ]; then
    ditto -c -k --sequesterRsrc --keepParent "$release_app" "$release_stage/notarization.zip"
    xcrun notarytool submit "$release_stage/notarization.zip" --keychain-profile "$NOTARY_PROFILE" --wait --timeout 10m --output-format json > "$release_output/notarization.json"
    python3 - "$release_output/notarization.json" <<'PY'
import json, sys
result = json.load(open(sys.argv[1]))
if result.get('status') != 'Accepted':
    raise SystemExit('Notarization was not accepted; do not publish this package.')
PY
    xcrun stapler staple "$release_app"
    xcrun stapler validate "$release_app"
    spctl --assess --type execute --verbose=2 "$release_app"
    release_notarized=true
fi
ditto -c -k --sequesterRsrc --keepParent "$release_app" "$release_archive"
# Validate the exact distributable after extraction, not just its pre-archive input.
mkdir "$release_stage/unpacked"
ditto -x -k "$release_archive" "$release_stage/unpacked"
codesign --verify --deep --strict "$release_stage/unpacked/RazerMouse.app"
# Complete corresponding source includes locked dependency sources. Research references
# and protocol extraction tools remain excluded, just as they are in the Git tree.
release_source_name="RazerMouse-v$release_version-source"
release_source="$release_stage/$release_source_name"
mkdir -p "$release_source/.cargo"
git archive HEAD | tar -x -C "$release_source"
(cd "$release_source" && cargo vendor --locked --versioned-dirs vendor > .cargo/config.toml)
COPYFILE_DISABLE=1 tar -czf "$release_output/$release_source_name.tar.gz" -C "$release_stage" "$release_source_name"
python3 - "$release_app" "$release_stage/signature.txt" "$release_output" "$release_revision" "$release_notarized" <<'PY'
import json, plistlib, subprocess, sys
from pathlib import Path
app, signature, output = map(Path, sys.argv[1:4])
info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
fields = {}
for line in signature.read_text().splitlines():
    key, sep, value = line.partition('=')
    if sep and key in ['Identifier', 'Authority', 'TeamIdentifier', 'Timestamp', 'CDHash']:
        fields.setdefault(key, []).append(value)
report = {
    'version': info['CFBundleShortVersionString'], 'build': info['CFBundleVersion'],
    'commit': sys.argv[4], 'architecture': subprocess.check_output(['lipo', '-archs', str(app / 'Contents/MacOS/RazerMouse')], text=True).strip(),
    'minimum_macos': info['LSMinimumSystemVersion'], 'signature': fields,
    'hardened_runtime': True, 'signature_verified_after_unzip': True,
    'notarized': sys.argv[5] == 'true',
}
(output / 'signature-report.json').write_text(json.dumps(report, indent=2) + '\n')
PY
(cd "$release_output" && shasum -a 256 "RazerMouse-v$release_version-macos-arm64.zip" "$release_source_name.tar.gz" signature-report.json > SHA256SUMS)
printf 'Release artifacts: %s\nApple notarized: %s\n' "$release_output" "$release_notarized"
