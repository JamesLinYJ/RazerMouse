# License and provenance

RazerMouse is released under **GPL-2.0-or-later**: GNU General Public License version 2, or (at your option) any later version. The full license is in [`../LICENSE`](../LICENSE). This covers project-authored source, documentation, tests and artwork. Third-party components retain their own licenses.

## OpenRazer reference

- Repository: https://github.com/openrazer/openrazer
- Pinned commit: `6820f9da169d354bc7e6e93a0aa8683a6bb75792`
- Upstream license: GPL-2.0-or-later.
- Relevant reference files: `driver/razermouse_driver.c`, `driver/razermouse_driver.h`, `driver/razercommon.h`, `driver/razerchromacommon.c`, `driver/razerchromacommon.h`, `daemon/openrazer_daemon/hardware/mouse.py`, and `daemon/openrazer_daemon/hardware/device_base.py`.
- Upstream notices include Copyright (c) 2015 Terri Cain and Copyright (c) 2015 Tim Theede. The pinned reference retains the complete original per-file notices and contribution history.

The Rust implementation consumes extracted catalog entries, constraints, command recipes and oracle vectors. During development, upstream command bodies were compiled into a recording-only test library. That research tooling and corpus are not included in this public repository or linked into the application. Rewriting implementation code or changing language does not constitute relicensing upstream material.

Runtime data preserves provenance through `docs/upstream.json` and source symbols. JSON does not support comment headers; this notice applies to `crates/razer-core/src/{catalog,recipes,limits}.json`, `docs/attributes.json`, and `app/Sources/RazerMouse/Resources/input-report-map.json`.

The reference checkout, oracle corpus, compiled test oracle and extraction/rewrite scripts are excluded from this public source tree. Historical comparison results are recorded as development evidence, not represented as reproducible by the default public test suite. No upstream C or Python code is linked into product targets.

## Dependencies and generated bindings

Rust dependencies are pinned by `Cargo.lock`; their package manifests and upstream repositories provide the applicable licenses. See [third-party notices](../THIRD_PARTY_NOTICES.md). UniFFI generates `RazerBindings.swift`, `RazerFFI.h` and the module map from this project's API. Generated headers are preserved and must not be replaced with misleading authorship statements.

The app is locally ad-hoc signed, not endorsed or signed by Razer. Razer and product names identify compatible hardware; the GPL does not grant rights to third-party trademarks.

## 中文摘要

本项目整体采用 GPL-2.0-or-later，即 GPL 第 2 版或你选择的任意更新版本。协议来源固定为上述 OpenRazer commit；生成数据、测试样本及相关实现保留来源和 GPL 许可。第三方依赖仍适用各自许可证。项目不声称获得雷蛇官方背书，也不通过软件许可证授予第三方商标权。
