// SPDX-License-Identifier: GPL-2.0-or-later
import AppKit
import SwiftUI
import XCTest

@testable import RazerMouse

final class VisualTests: XCTestCase {
  func testRoundedPercentageEndpointRemainsWritable() {
    XCTAssertEqual(PowerAdjustmentValue.raw(displayed: 25, percentage: true, minimum: 12, maximum: 63), 63)
    XCTAssertNil(PowerAdjustmentValue.raw(displayed: 30, percentage: true, minimum: 12, maximum: 63))
    XCTAssertNil(PowerAdjustmentValue.raw(displayed: 59, percentage: false, minimum: 60, maximum: 900))
    XCTAssertEqual(PowerAdjustmentValue.raw(displayed: 300, percentage: false, minimum: 60, maximum: 900), 300)
  }
  func testDpiAdjustmentUsesDeviceRangeAndDiscreteValues() {
    XCTAssertEqual(DpiAdjustment.value(position: 0, minimum: 100, maximum: 45000, supported: []), 100)
    XCTAssertEqual(DpiAdjustment.value(position: 30, minimum: 100, maximum: 45000, supported: []), 45000)
    XCTAssertEqual(DpiAdjustment.value(position: log2(1600), minimum: 100, maximum: 45000, supported: []), 1600)
    XCTAssertEqual(DpiAdjustment.value(position: log2(900), minimum: 400, maximum: 1600, supported: [400, 800, 1600]), 800)
  }
  @MainActor func testPopoverBackingCoversResizedEdgesInBothAppearances() throws {
    for appearance in [NSAppearance.Name.aqua, .darkAqua] {
      let backing = OpaquePopoverView(frame: .zero)
      backing.appearance = NSAppearance(named: appearance)
      let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 500), styleMask: .borderless, backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      window.contentView = backing
      defer { window.close() }
      for height in [500, 730, 650] {
        window.setContentSize(NSSize(width: 360, height: height))
        backing.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(backing.bitmapImageRepForCachingDisplay(in: backing.bounds))
        backing.cacheDisplay(in: backing.bounds, to: bitmap)
        for x in [0, bitmap.pixelsWide / 2, bitmap.pixelsWide - 1] {
          for y in [0, 10, bitmap.pixelsHigh - 11, bitmap.pixelsHigh - 1] {
            let color = try XCTUnwrap(bitmap.colorAt(x: x, y: y))
            XCTAssertEqual(color.alphaComponent, 1, accuracy: 0.001, "Popover edges must remain opaque after resizing")
          }
        }
      }
    }
  }
  @MainActor func testVisualStates() throws {
    let folder =
      ProcessInfo.processInfo.environment["RAZER_SCREENSHOT_DIR"] ?? NSTemporaryDirectory()
      + "razer-visuals"
    try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
    RenderQA.render(to: folder)
    RenderQA.renderSettings(to: folder)
    for variant in ["normal", "power", "lighting", "long", "disconnected", "macros", "info", "wheel", "sync"] {
      for scheme in ["light", "dark"] {
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder + "/settings-\(variant)-\(scheme).png"))
      }
    }
    for variant in [
      "normal", "low", "charging", "long", "disconnected", "error", "lighting", "unread",
      "multiple", "power", "stages",
    ] {
      for scheme in ["light", "dark"] {
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder + "/\(variant)-\(scheme).png"))
      }
    }
  }
  @MainActor func testInvalidDpiRestoresConfirmedReading() {
    let model = MouseModel(monitoring: false)
    model.installPreview("normal")
    model.dpiText = "invalid"
    model.setDpi()
    XCTAssertEqual(model.dpiText, String(model.state!.dpi!.x))
    XCTAssertTrue(model.failed)
  }
  @MainActor func testUnknownStateHasNoInventedSettings() {
    let model = MouseModel(monitoring: false)
    XCTAssertNil(model.state)
    XCTAssertTrue(model.dpiText.isEmpty)
    XCTAssertTrue(model.devices.isEmpty)
    XCTAssertTrue(model.advancedValues.isEmpty)
    XCTAssertEqual(model.batteryText, "—")
  }
  @MainActor func testUnplugReplugAndDeviceReplacement() {
    let model = MouseModel(monitoring: false)
    model.installPreview("normal")
    let device = model.devices[0]
    let originalDpi = model.state?.dpi?.x
    XCTAssertFalse(model.reconcileDevices([]))
    XCTAssertFalse(model.connected)
    XCTAssertEqual(model.state?.dpi?.x, originalDpi, "Disconnected readings remain explicitly stale")
    XCTAssertTrue(model.connectionNotice.contains("断开"))
    XCTAssertTrue(model.reconcileDevices([device]))
    XCTAssertTrue(model.connected)
    XCTAssertNil(model.state, "Reconnection must read hardware before showing current settings")
    var replacement = device
    replacement.id = "different-physical-device"
    XCTAssertTrue(model.reconcileDevices([replacement]))
    XCTAssertEqual(model.selected, replacement.id)
    XCTAssertTrue(model.dpiText.isEmpty)
  }
}

@MainActor enum RenderQA {
  static func render(to folder: String) {
    for variant in [
      "normal", "low", "charging", "long", "disconnected", "error", "lighting", "unread",
      "multiple", "power", "stages",
    ] {
      let model = MouseModel(monitoring: false)
      model.installPreview(variant)
      for scheme in [ColorScheme.light, .dark] {
        let section = variant == "power" ? "电源" : variant == "lighting" ? "灯光" : "常用"
        let view = NSHostingView(rootView: Panel(model: model, section: section, editingStages: variant == "stages")
          .environment(\.colorScheme, scheme))
        view.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        let size = view.fittingSize
        view.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(
          contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = view
        window.isReleasedWhenClosed = false
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        view.displayIfNeeded()
        if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
          view.cacheDisplay(in: view.bounds, to: bitmap)
          try? bitmap.representation(using: .png, properties: [:])?.write(
            to: URL(
              fileURLWithPath: folder + "/\(variant)-\(scheme == .dark ? "dark" : "light").png"))
        }
        window.close()

      }
    }
  }
}


extension RenderQA {
  static func renderSettings(to folder: String) {
    for variant in ["normal", "power", "lighting", "long", "disconnected", "macros", "info", "wheel", "sync"] {
      let model = MouseModel(monitoring: false)
      model.installPreview(variant)
      for scheme in [ColorScheme.light, .dark] {
        let tab = ["power", "lighting", "macros", "info", "wheel"].contains(variant) ? variant : variant == "sync" ? "lighting" : "performance"
        let view = NSHostingView(rootView: SettingsView(model: model, tab: tab).environment(\.colorScheme, scheme))
        view.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        view.frame = NSRect(origin: .zero, size: view.fittingSize)
        let window = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = view
        window.isReleasedWhenClosed = false
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        view.displayIfNeeded()
        if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
          view.cacheDisplay(in: view.bounds, to: bitmap)
          try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: folder + "/settings-\(variant)-\(scheme == .dark ? "dark" : "light").png"))
        }
        window.close()
      }
    }
  }
}
