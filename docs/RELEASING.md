# Certificate-signed releases

Local development builds remain ad-hoc signed. Distribution builds use an existing **Developer ID Application** identity from the macOS keychain; the release script requires its SHA-1 fingerprint, enables Hardened Runtime and a secure timestamp, and verifies both the app and the extracted ZIP.

```sh
security find-identity -v -p codesigning
SIGN_IDENTITY="YOUR_DEVELOPER_ID_SHA1" ./scripts/release.sh
```

Commit changes first. The script builds the exact current source and writes artifacts beneath `build/release/v<version>/`. It never exports private keys or stores credentials in the repository. The certificate's Apple-issued subject identifies the developer; the app bundle identifier remains `org.razermouse.app`.

To also notarize, supply the name of an existing notarytool keychain profile:

```sh
SIGN_IDENTITY="YOUR_DEVELOPER_ID_SHA1" NOTARY_PROFILE="YOUR_KEYCHAIN_PROFILE" ./scripts/release.sh
```

The script submits to Apple, requires `Accepted`, staples the ticket and runs Gatekeeper assessment. Without a profile, it creates a **signed but unnotarized** package. Release notes must state that distinction: a valid certificate signature alone does not establish Gatekeeper acceptance on a newly downloaded app. Never advertise notarization based on a codesign success.

Artifacts include the app ZIP, SHA-256 checksums, a signature report and complete corresponding source with locked Cargo dependency sources. The source archive does not include OpenRazer research checkouts, oracle samples or extraction/rewrite scripts. The dependency source archive supports rebuilding the distributed GPL application; it is not added to the Git repository.

Before publishing, run the public test suite, check the archive and source inventory, and verify the Git tag matches the signature report's commit. Upload assets to a draft GitHub release, then publish after confirming checksums and signature state. Preserve `Co-authored-by: Codex <codex@openai.com>` for Codex-assisted release preparation commits.

## DMG installer

The preferred download is a Finder drag-to-Applications disk image. Its original background is rendered with AppKit from the project's SVG artwork at 1× and 2×; `dmgbuild` supplies the native icon positions, Applications shortcut and Retina background. No installer executable or privileged helper is added.

```sh
python3 -m venv .venv
.venv/bin/pip install dmgbuild==1.6.5
NOTARIZED_APP="/path/to/RazerMouse.app" \
SIGN_IDENTITY="YOUR_DEVELOPER_ID_SHA1" \
NOTARY_PROFILE="YOUR_KEYCHAIN_PROFILE" \
DMG_PYTHON=.venv/bin/python ./scripts/build-dmg.sh
```

Use a previously notarized, stapled app. Without `NOTARY_PROFILE`, this command only signs the DMG and explicitly leaves container notarization pending. Before distribution, the **DMG itself** must pass all of:

```sh
xcrun stapler validate /path/to/RazerMouse.dmg
codesign --verify --strict /path/to/RazerMouse.dmg
spctl --assess --type open --context context:primary-signature --verbose=2 /path/to/RazerMouse.dmg
hdiutil verify /path/to/RazerMouse.dmg
```

Also mount the final image, check its app signature/ticket/Gatekeeper assessment and inspect a newly opened Finder window. The layout reserves space for Finder chrome so first-launch guidance stays visible. `docs/screenshots/installer.png` records the actual v0.1.0 installer, not a mockup.

### Existing Xcode account alternative

The first release used Xcode's already signed-in Developer ID account, without extracting credentials: a valid app `.xcarchive`, `xcodebuild -exportArchive` with Developer ID/upload export options and `-allowProvisioningUpdates`, followed by `xcodebuild -exportNotarizedApp`. The app's attached ticket and Gatekeeper acceptance were checked independently.

For the DMG, the signed image was included as a resource in a separately re-signed temporary submission app and submitted through the same Xcode flow. Apple's notarization service [processes nested containers](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow). The submission app was never distributed. The original DMG subsequently received its own ticket through `stapler staple` and passed the checks above. Prefer the direct notarytool profile workflow for repeatable automated releases.

Record app and packaging commits separately when only the installer changes after the app is built. Keep the app tag and corresponding-source archive aligned with the app's actual source commit; link the packaging commit in the release report. Recompute checksums after stapling, download the uploaded assets to verify them, and only then publish the draft.
