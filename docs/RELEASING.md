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
