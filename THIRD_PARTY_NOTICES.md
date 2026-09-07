# Third-party notices

The project is GPL-2.0-or-later. This list records the locked Cargo workspace dependency graph, including build tools and target-specific dependencies; it does not imply every listed package is linked into the macOS application. License alternatives are quoted from package metadata, not replaced by the project license. Full dependency source and notices are available through Cargo and the linked upstream repositories.

## Protocol reference

[OpenRazer](https://github.com/openrazer/openrazer/tree/6820f9da169d354bc7e6e93a0aa8683a6bb75792), GPL-2.0-or-later. Relevant upstream copyright notices include Terri Cain (2015) and Tim Theede (2015). See [provenance](docs/LICENSING.md) and the pinned source for full per-file notices.

## Native libraries

- [hidapi](https://github.com/libusb/hidapi): the hidapi Rust package includes native HIDAPI code, available under its upstream license alternatives (GPLv3, BSD-style, or original HIDAPI license). Retain the applicable notices when distributing native code; see the vendored source in the locked Cargo package.
- [libusb](https://github.com/libusb/libusb): LGPL-2.1-or-later; built through libusb1-sys with vendoring enabled. A binary distributor must also satisfy the native library's source and linking obligations. This repository publication contains source, not a binary release.
- UniFFI binding templates retain their upstream notices. System frameworks (AppKit, SwiftUI, IOKit, CoreGraphics and others) are provided by macOS/Xcode.

## Cargo packages

| Package | Locked version | Declared license | Upstream |
| --- | --- | --- | --- |
| anstyle | 1.0.14 | MIT OR Apache-2.0 | [Source](https://github.com/rust-cli/anstyle.git) |
| anyhow | 1.0.104 | MIT OR Apache-2.0 | [Source](https://github.com/dtolnay/anyhow) |
| askama | 0.13.1 | MIT OR Apache-2.0 | [Source](https://github.com/askama-rs/askama) |
| askama_derive | 0.13.1 | MIT OR Apache-2.0 | [Source](https://github.com/askama-rs/askama) |
| askama_parser | 0.13.0 | MIT OR Apache-2.0 | [Source](https://github.com/askama-rs/askama) |
| autocfg | 1.5.1 | Apache-2.0 OR MIT | [Source](https://github.com/cuviper/autocfg) |
| basic-toml | 0.1.10 | MIT OR Apache-2.0 | [Source](https://github.com/dtolnay/basic-toml) |
| bitflags | 2.13.1 | MIT OR Apache-2.0 | [Source](https://github.com/bitflags/bitflags) |
| bytes | 1.12.1 | MIT | [Source](https://github.com/tokio-rs/bytes) |
| camino | 1.2.5 | MIT OR Apache-2.0 | [Source](https://github.com/camino-rs/camino) |
| cargo-platform | 0.1.9 | MIT OR Apache-2.0 | [Source](https://github.com/rust-lang/cargo) |
| cargo_metadata | 0.19.2 | MIT | [Source](https://github.com/oli-obk/cargo_metadata) |
| cc | 1.4.5 | MIT OR Apache-2.0 | [Source](https://github.com/rust-lang/cc-rs) |
| cfg-if | 1.0.4 | MIT OR Apache-2.0 | [Source](https://github.com/rust-lang/cfg-if) |
| clap | 4.6.6 | MIT OR Apache-2.0 | [Source](https://github.com/clap-rs/clap) |
| clap_builder | 4.6.6 | MIT OR Apache-2.0 | [Source](https://github.com/clap-rs/clap) |
| clap_derive | 4.6.4 | MIT OR Apache-2.0 | [Source](https://github.com/clap-rs/clap) |
| clap_lex | 1.1.0 | MIT OR Apache-2.0 | [Source](https://github.com/clap-rs/clap) |
| equivalent | 1.0.2 | Apache-2.0 OR MIT | [Source](https://github.com/indexmap-rs/equivalent) |
| errno | 0.3.14 | MIT OR Apache-2.0 | [Source](https://github.com/lambda-fairy/rust-errno) |
| fastrand | 2.5.0 | Apache-2.0 OR MIT | [Source](https://github.com/smol-rs/fastrand) |
| find-msvc-tools | 0.1.12 | MIT OR Apache-2.0 | [Source](https://github.com/rust-lang/cc-rs) |
| fs-err | 2.11.0 | MIT/Apache-2.0 | [Source](https://github.com/andrewhickman/fs-err) |
| getrandom | 0.4.3 | MIT OR Apache-2.0 | [Source](https://github.com/rust-random/getrandom) |
| glob | 0.3.4 | MIT OR Apache-2.0 | [Source](https://github.com/rust-lang/glob) |
| goblin | 0.8.2 | MIT | [Source](https://github.com/m4b/goblin) |
| hashbrown | 0.17.1 | MIT OR Apache-2.0 | [Source](https://github.com/rust-lang/hashbrown) |
| heck | 0.5.0 | MIT OR Apache-2.0 | [Source](https://github.com/withoutboats/heck) |
| hidapi | 2.6.7 | MIT | [Source](https://github.com/ruabmbua/hidapi-rs) |
| indexmap | 2.14.2 | Apache-2.0 OR MIT | [Source](https://github.com/indexmap-rs/indexmap) |
| itoa | 1.0.18 | MIT OR Apache-2.0 | [Source](https://github.com/dtolnay/itoa) |
| libc | 0.2.189 | MIT OR Apache-2.0 | [Source](https://github.com/rust-lang/libc) |
| libusb1-sys | 0.7.0 | MIT | [Source](https://github.com/a1ien/rusb.git) |
| linux-raw-sys | 0.12.1 | Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT | [Source](https://github.com/sunfishcode/linux-raw-sys) |
| log | 0.4.34 | MIT OR Apache-2.0 | [Source](https://github.com/rust-lang/log) |
| memchr | 2.8.3 | Unlicense OR MIT | [Source](https://github.com/BurntSushi/memchr) |
| minimal-lexical | 0.2.1 | MIT/Apache-2.0 | [Source](https://github.com/Alexhuszagh/minimal-lexical) |
| nom | 7.1.3 | MIT | [Source](https://github.com/Geal/nom) |
| once_cell | 1.21.4 | MIT OR Apache-2.0 | [Source](https://github.com/matklad/once_cell) |
| percent-encoding | 2.3.2 | MIT OR Apache-2.0 | [Source](https://github.com/servo/rust-url/) |
| pin-project-lite | 0.2.17 | Apache-2.0 OR MIT | [Source](https://github.com/taiki-e/pin-project-lite) |
| pkg-config | 0.3.34 | MIT OR Apache-2.0 | [Source](https://github.com/rust-lang/pkg-config-rs) |
| plain | 0.2.3 | MIT/Apache-2.0 | [Source](https://github.com/randomites/plain) |
| proc-macro2 | 1.0.107 | MIT OR Apache-2.0 | [Source](https://github.com/dtolnay/proc-macro2) |
| quote | 1.0.47 | MIT OR Apache-2.0 | [Source](https://github.com/dtolnay/quote) |
| r-efi | 6.0.0 | MIT OR Apache-2.0 OR LGPL-2.1-or-later | [Source](https://github.com/r-efi/r-efi) |
| rusb | 0.9.4 | MIT | [Source](https://github.com/a1ien/rusb.git) |
| rustc-hash | 2.1.3 | Apache-2.0 OR MIT | [Source](https://github.com/rust-lang/rustc-hash) |
| rustix | 1.1.4 | Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT | [Source](https://github.com/bytecodealliance/rustix) |
| scroll | 0.12.0 | MIT | [Source](https://github.com/m4b/scroll) |
| scroll_derive | 0.12.1 | MIT | [Source](https://github.com/m4b/scroll) |
| semver | 1.0.28 | MIT OR Apache-2.0 | [Source](https://github.com/dtolnay/semver) |
| serde | 1.0.229 | MIT OR Apache-2.0 | [Source](https://github.com/serde-rs/serde) |
| serde_core | 1.0.229 | MIT OR Apache-2.0 | [Source](https://github.com/serde-rs/serde) |
| serde_derive | 1.0.229 | MIT OR Apache-2.0 | [Source](https://github.com/serde-rs/serde) |
| serde_json | 1.0.151 | MIT OR Apache-2.0 | [Source](https://github.com/serde-rs/json) |
| shlex | 2.0.1 | MIT OR Apache-2.0 | [Source](https://github.com/comex/rust-shlex) |
| siphasher | 0.3.11 | MIT/Apache-2.0 | [Source](https://github.com/jedisct1/rust-siphash) |
| smawk | 0.3.3 | MIT | [Source](https://github.com/mgeisler/smawk) |
| static_assertions | 1.1.0 | MIT OR Apache-2.0 | [Source](https://github.com/nvzqz/static-assertions-rs) |
| strsim | 0.11.1 | MIT | [Source](https://github.com/rapidfuzz/strsim-rs) |
| syn | 2.0.119 | MIT OR Apache-2.0 | [Source](https://github.com/dtolnay/syn) |
| syn | 3.0.5 | MIT OR Apache-2.0 | [Source](https://github.com/dtolnay/syn) |
| tempfile | 3.27.0 | MIT OR Apache-2.0 | [Source](https://github.com/Stebalien/tempfile) |
| textwrap | 0.16.2 | MIT | [Source](https://github.com/mgeisler/textwrap) |
| thiserror | 2.0.20 | MIT OR Apache-2.0 | [Source](https://github.com/dtolnay/thiserror) |
| thiserror-impl | 2.0.20 | MIT OR Apache-2.0 | [Source](https://github.com/dtolnay/thiserror) |
| toml | 0.5.11 | MIT/Apache-2.0 | [Source](https://github.com/toml-rs/toml) |
| tracing | 0.1.44 | MIT | [Source](https://github.com/tokio-rs/tracing) |
| tracing-attributes | 0.1.31 | MIT | [Source](https://github.com/tokio-rs/tracing) |
| tracing-core | 0.1.36 | MIT | [Source](https://github.com/tokio-rs/tracing) |
| unicode-ident | 1.0.24 | (MIT OR Apache-2.0) AND Unicode-3.0 | [Source](https://github.com/dtolnay/unicode-ident) |
| uniffi | 0.29.5 | MPL-2.0 | [Source](https://github.com/mozilla/uniffi-rs) |
| uniffi_bindgen | 0.29.5 | MPL-2.0 | [Source](https://github.com/mozilla/uniffi-rs) |
| uniffi_core | 0.29.5 | MPL-2.0 | [Source](https://github.com/mozilla/uniffi-rs) |
| uniffi_internal_macros | 0.29.5 | MPL-2.0 | [Source](https://github.com/mozilla/uniffi-rs) |
| uniffi_macros | 0.29.5 | MPL-2.0 | [Source](https://github.com/mozilla/uniffi-rs) |
| uniffi_meta | 0.29.5 | MPL-2.0 | [Source](https://github.com/mozilla/uniffi-rs) |
| uniffi_pipeline | 0.29.5 | MPL-2.0 | [Source](https://github.com/mozilla/uniffi-rs) |
| uniffi_udl | 0.29.5 | MPL-2.0 | [Source](https://github.com/mozilla/uniffi-rs) |
| vcpkg | 0.2.15 | MIT/Apache-2.0 | [Source](https://github.com/mcgoo/vcpkg-rs) |
| weedle2 | 5.0.0 | MIT | [Source](https://github.com/mozilla/uniffi-rs) |
| windows-link | 0.2.1 | MIT OR Apache-2.0 | [Source](https://github.com/microsoft/windows-rs) |
| windows-sys | 0.61.2 | MIT OR Apache-2.0 | [Source](https://github.com/microsoft/windows-rs) |
| winnow | 0.7.15 | MIT | [Source](https://github.com/winnow-rs/winnow) |
| zmij | 1.0.23 | MIT | [Source](https://github.com/dtolnay/zmij) |
