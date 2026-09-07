<div align="center">
  <img src="design/app-icon.svg" width="104" alt="Razer Mouse icon" />
  <h1>RazerMouse</h1>
  <p>A native macOS control panel for Razer mice.</p>
  <p>SwiftUI · Rust · UniFFI · macOS 14+ · Apple Silicon</p>
  <p><b>English</b> · <a href="README.zh-CN.md">简体中文</a></p>
</div>

Change DPI, polling rate, power settings and supported lighting directly from the menu bar. The app calls a statically linked Rust core through UniFFI; it has no product CLI, WebView or separate background service.

**Status:** early development. DeathAdder V4 Pro wired and wireless paths have received hardware testing; other catalog entries have protocol comparison coverage, not hardware certification. The interface is currently in Chinese. This is an independent project, not an official Razer product.

## Preview

<table>
  <tr>
    <td width="34%"><img src="docs/screenshots/widget-dark.png" alt="Dark menu bar control panel" /></td>
    <td><img src="docs/screenshots/settings-light.png" alt="Light settings window with sidebar and performance controls" /></td>
  </tr>
  <tr><td align="center">Menu bar controls</td><td align="center">Detailed settings</td></tr>
</table>

These images render the actual SwiftUI views with **simulated device data**. They illustrate appearance, not hardware test results.

## Features

- **Performance:** editable DPI, stage selection and editing, polling rates, and device-specific ranges.
- **Power:** battery and charging status, idle timeout, low-battery threshold, stale readings on disconnect.
- **Lighting:** capability-driven zones, effects, colors, brightness, custom frames and explicit effect synchronization across compatible devices.
- **Wheel and macros:** supported hardware wheel controls; local tilt actions, keyboard macro recording, trigger learning and saved bindings. Software actions preserve native input and default to off.
- **Device information:** connection, firmware, serial number and supported controls.
- **Native behavior:** SVG icons, semantic colors, light/dark appearance, accessible control labels and reduced-motion support. An opaque AppKit popover hosts the SwiftUI panel.

Controls only appear when the selected device advertises support. Reconnection reads the device without automatically applying presets. Synapse is detected and a conflict hint is shown; the app does not terminate it.

## Downloads

Certificate-signed Apple Silicon packages are published on [GitHub Releases](https://github.com/JamesLinYJ/RazerMouse/releases). Check each release's signature report and notarization status before installing. Source builds below use ad-hoc signing by default; see [release packaging](docs/RELEASING.md) for Developer ID signing.

## Build

Requirements: an Apple Silicon Mac, macOS 14 or later, Xcode with a Swift 5.9+ toolchain and macOS SDK, Rust/Cargo, Python 3 and Git. Development validation used Rust 1.98 and a Swift 6.4 beta toolchain; other supported toolchain combinations have not all been tested.

```sh
git clone https://github.com/JamesLinYJ/RazerMouse.git
cd RazerMouse
./scripts/build.sh
```

Output: `build/RazerMouse.app`. Copy it to your Applications folder and open it. The build generates Swift ABI bindings, compiles resources and signs locally with the neutral identifier `org.razermouse.app`. This is an **ad-hoc signed development build**, not a notarized release.

If Xcode is installed outside the default location, set `DEVELOPER_DIR` to its `Contents/Developer` directory before building. Do not change the repository to contain machine-specific Xcode paths.

### Permissions

HID access may require **System Settings → Privacy & Security → Input Monitoring**. The app provides a settings shortcut when access is denied. A changed ad-hoc signature can require refreshing the app's permission entry and restarting it.

**Accessibility** is separate and only needed for synthesized macro/tilt output. Macro recording is confined to the focused recording view. Bindings and presets are local; device serial numbers are not uploaded by the application.

## Tests

```sh
./scripts/test.sh
```

Default tests do not control real hardware. They exercise protocol validation and local state, and render 40 visual fixtures into `build/screenshots/`. The public suite has 6 Rust and 11 Swift tests; an external-corpus differential test and 2 hardware tests are excluded from the default run. During local development, 5,854 upstream oracle cases passed comparison; that corpus is not published here.

To explicitly opt into connected-device **read-only** tests:

```sh
RAZER_HARDWARE_READ=1 ./scripts/test.sh
```

The protocol reference is OpenRazer commit `6820f9da169d354bc7e6e93a0aa8683a6bb75792`. The repository includes the runtime device catalog, limits and wire recipes needed to build the app. **Upstream source checkouts, reference samples and extraction/rewrite scripts are not included.** Normal builds and tests do not download or compile OpenRazer. UniFFI binding generation remains part of the ordinary build.

## Architecture

| Location | Responsibility |
| --- | --- |
| `crates/razer-core/src/protocol.rs`, `wire.rs`, `engine.rs` | Typed protocol, framing, response checks and transport contract |
| `crates/razer-core/src/backend.rs` | Non-exclusive HID/USB communication on one persistent OS thread |
| `crates/razer-core/src/controller.rs` | UniFFI API, capabilities, typed settings and readback |
| `app/Sources/RazerMouse/Model.swift` | Asynchronous state, refreshes, confirmed values and feedback |
| `app/Sources/RazerMouse/StatusPopover.swift` | Native menu bar item, opaque popover and content sizing |
| `app/Sources/RazerMouse/InputActions.swift` | macOS input monitoring and cancellable local actions |
| `scripts/`, `tools/bindgen/` | App building, ABI binding generation, icon packaging and validation |

IOKit notifications trigger device refresh; a five-second enumeration is the fallback. Battery refresh runs every 60 seconds, with refreshes on launch and panel opening. Native HID handles remain on their owning OS thread: a serial queue alone does not guarantee macOS RunLoop affinity.

## Verification boundaries

| Area | Evidence |
| --- | --- |
| Protocol catalog | 113 mouse/receiver PIDs; 5,854 differential cases |
| V4 Pro wired | Reads and native settings writes/readback tested |
| V4 Pro wireless | Single reads; widget DPI, stages, polling and idle writes/readback tested and restored |
| Native popover | Connected panel, power page, expanded stages, invalid-input recovery, close/reopen checked locally |
| Other hardware | Not hardware-verified; one wireless repeated-read run timed out |
| Macro output, tilt, multi-device lighting | Software tests/UI available; actual output still needs permission or matching hardware |
| Hotplug latency, sleep/wake, restart | Full end-to-end acceptance remains pending |

See [coverage](docs/coverage.md) for the per-model matrix and historical measurements. The newest installed bundle measured about 6.04 MB; current-release idle CPU and memory have not been remeasured. Earlier measurements must not be presented as current-release results.

## Contributing and licenses

Read [AGENTS.md](AGENTS.md) for architecture and validation rules, and [the design notes](design/README.md) before changing controls.

This project is licensed under **[GPL-2.0-or-later](LICENSE)**. It builds on protocol evidence and generated data from [OpenRazer](https://github.com/openrazer/openrazer). Upstream and dependency notices are preserved; see [licensing and provenance](docs/LICENSING.md) and [third-party notices](THIRD_PARTY_NOTICES.md).
