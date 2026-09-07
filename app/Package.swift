// swift-tools-version: 5.9
// SPDX-License-Identifier: GPL-2.0-or-later
import PackageDescription
import Foundation
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().path
let package = Package(name: "RazerMouse", platforms: [.macOS(.v14)], products: [.executable(name: "RazerMouse", targets: ["RazerMouse"])], targets: [
 .target(name: "RazerFFI", path: "Sources/RazerFFI", publicHeadersPath: "include"),
 .target(name: "RazerBindings", dependencies: ["RazerFFI"], linkerSettings: [.unsafeFlags([root + "/target/release/librazer_core.a"]), .linkedFramework("IOKit"), .linkedFramework("CoreFoundation"), .linkedFramework("Security"), .linkedLibrary("objc")]),
 .executableTarget(name: "RazerMouse", dependencies: ["RazerBindings"], resources: [.process("Resources")]),
 .testTarget(name: "RazerMouseTests", dependencies: ["RazerMouse", "RazerBindings"])
])
