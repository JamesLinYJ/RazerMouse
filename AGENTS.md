# Working on RazerMouse

## Scope and architecture

- Native macOS 14+ / Apple Silicon app. SwiftUI and AppKit own presentation; idiomatic Rust owns the control protocol. Communicate through the statically linked UniFFI ABI.
- Do not add a product CLI, WebView, background daemon, kernel extension, or C-to-Rust line-by-line translation.
- `tools/bindgen` is a build-time utility, not a user-facing CLI.
- Hardware knowledge comes from the pinned OpenRazer reference and generated profiles. Do not invent device values or add ad hoc PID branches in presentation code.
- OpenRazer mouse and related receiver functionality is the scope. Keyboard, headset and upstream-unimplemented hardware features are outside it.

## Before editing

Read both READMEs, `docs/LICENSING.md`, and the relevant module. Check current tests and generated-data provenance before changing a protocol route. Preserve unrelated user changes. Do not assume a device is connected or that Synapse is stopped.

## Communication and device invariants

- Native hidapi handles, enumeration, exchange and close belong to the persistent `razer.hid` OS thread in `backend.rs`. A serial DispatchQueue is insufficient for RunLoop affinity.
- Keep blocking I/O off the main actor. Serialize each device's operations; do not automatically replay non-idempotent writes.
- Verify responses and read back settings when a getter exists. Otherwise describe the result as sent, not confirmed hardware state.
- Failed edits restore confirmed values. Unknown readings remain unknown; disconnected readings remain explicitly stale.
- Reconnect must not apply presets or overwrite the hardware. Keep pending hotplug notifications while a write is busy.
- Keep IOKit hotplug notifications and the enumeration fallback. Pause monitoring during sleep and stop local input actions on disconnect.
- Macro playback must remain cancellable, bounded, tied to the intended foreground process, and release held keys when stopped. Recording must stay local to the focused view. Do not silently grant permissions or enable macros on startup.

## UI rules

- Follow `design/README.md`: SVG assets, semantic colors, restrained green emphasis, accessible names, keyboard interaction and system accessibility preferences.
- Keep the native `NSStatusItem + NSPopover` host and its opaque root backing. Do not reintroduce MenuBarExtra safe-area fixes without evidence from an actual menu bar popover.
- A ScrollView needs an explicit usable viewport in the popover. Check header/footer edges and resizing when switching tabs, expanding stages and showing errors.
- Render light/dark, long names, low battery, charging, disconnect and error states. Mock screenshots do not prove host behavior or hardware writes.
- Preview data belongs only in `app/Tests`; never add a simulated-device switch to the production app.

## Runtime data, bindings and provenance

The public repository deliberately excludes upstream checkouts, oracle samples and extraction/rewrite scripts. Do not add them back. Keep the runtime device catalog, wire recipes and limits: they are required source data for the application. Maintain those tables with traceable protocol evidence and validate affected routes and parameter boundaries.

Generated UniFFI bindings must not be hand-edited: change the Rust ABI and run `./scripts/build.sh`. This builds the Rust release library, Swift bindings, app, resources and local ad-hoc signature. `docs/upstream.json` records the reference repository and commit; changing it requires corresponding evidence and a coverage update.

## Validation

Run checks appropriate to the change. `./scripts/test.sh` runs Rust/Swift tests and generates visual fixtures without hardware access. Build the app after Swift, ABI, asset or packaging changes. Rust behavior changes require relevant boundary/failure tests. If an external oracle corpus is available, explicitly run the ignored differential test with `RAZER_ORACLE_VECTORS`; never report a skipped or empty corpus as a pass.

Real hardware tests are opt-in: `RAZER_HARDWARE_READ=1 ./scripts/test.sh`. Do not run write tests unless within the user's authorized scope; record and restore original settings, and report if a value cannot safely be restored. Never exit Synapse or change system permissions as an incidental test setup step.

Report separately: protocol comparison passed, real hardware passed, simulated visual checks, and unverified hardware. Do not claim performance targets from stale measurements. Avoid trivial implementation-mirroring tests for comments or documentation.

## Publication and licensing

- Project-authored source and artwork use GPL-2.0-or-later. Read `docs/LICENSING.md` and retain upstream and third-party licenses; do not relabel dependencies.
- Preserve third-party notices and pinned-source attribution. Do not copy reference C/Python into product targets.
- Never commit `reference/`, build products, caches, signing identities, credentials, personal device serial numbers, local preference exports or machine-specific test reports.
- Screenshots in public documentation must contain only app UI and clearly identify simulated fixtures.
- Keep the bundle identifier `org.razermouse.app` and build paths neutral. Do not embed a developer's home directory or local Xcode path.
- Keep English and Chinese READMEs consistent when changing public behavior.

`CLAUDE.md` is a relative symbolic link to this file; keep one canonical instruction source.
