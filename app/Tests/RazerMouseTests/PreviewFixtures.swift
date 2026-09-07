// SPDX-License-Identifier: GPL-2.0-or-later
import RazerBindings
import SwiftUI

@testable import RazerMouse

// Deliberately synthetic test data. This file is never linked into the app.
extension MouseModel {
  func installPreview(_ variant: String) {
    let advanced = ["lighting", "wheel", "sync"].contains(variant)
    let attrs =
      [
        "charge_level", "charge_status", "dpi", "dpi_stages", "poll_rate", "device_idle_time",
        "charge_low_threshold", "firmware_version", "device_serial",
      ]
      + (advanced
        ? [
          "logo_led_brightness", "logo_matrix_effect_static", "logo_matrix_effect_none",
          "logo_matrix_effect_spectrum", "logo_matrix_effect_breath", "logo_matrix_effect_wave", "logo_matrix_effect_reactive", "scroll_led_brightness", "scroll_matrix_effect_static", "left_led_brightness", "left_matrix_effect_static", "matrix_custom_frame", "matrix_effect_custom", "scroll_mode",
        ] : [])
    let d = DeviceInfo(
      id: "preview",
      name: variant == "long"
        ? "Razer DeathAdder V4 Pro White Edition · 工作室" : "Razer DeathAdder V4 Pro", pid: 190,
      connection: "无线接收器", maxDpi: 45000, minDpi: 100, maxStages: 5,
      ranges: [
        ControlRange(name: "logo_led_brightness", minimum: 0, maximum: 255),
        ControlRange(name: "device_idle_time", minimum: 60, maximum: 900),
        ControlRange(name: "charge_low_threshold", minimum: 12, maximum: 63),
      ], readableAttributes: attrs, cachedAttributes: [],
      pollRates: [125, 500, 1000, 2000, 4000, 8000],
      attributes: attrs, dpiList: [], ledCount: 1, tiltSupported: advanced)
    advancedValues = advanced ? ["logo_led_brightness": "127", "scroll_led_brightness": "90", "left_led_brightness": "220", "scroll_mode": "1", "device_serial": "PREVIEW-ONLY"] : ["device_serial": "PREVIEW-ONLY"]
    dpiText = "1600"
    devices = [d]
    selected = d.id
    connected = variant != "disconnected"
    state = Snapshot(
      device: d, battery: variant == "low" ? 9 : 76, charging: variant == "charging",
      dpi: DpiStage(x: 1600, y: 1600),
      stages: [400, 800, 1600, 3200, 6400].map { DpiStage(x: UInt32($0), y: UInt32($0)) },
      activeStage: 3, pollRate: 1000, idleSeconds: 300, lowBattery: 38, firmware: "v1.20",
      errors: [])
    if variant == "unread", var snapshot = state {
      snapshot.battery = nil
      snapshot.charging = nil
      snapshot.dpi = nil
      snapshot.stages = []
      snapshot.activeStage = nil
      snapshot.pollRate = nil
      snapshot.idleSeconds = nil
      snapshot.lowBattery = nil
      snapshot.firmware = nil
      state = snapshot
      dpiText = ""
    }
    if variant == "multiple" || variant == "sync" {
      var second = d
      second.id = "preview-second"
      second.name = "第二只模拟设备"
      devices.append(second)
    }
    if variant == "macros" {
      modelPreviewMacros()
    }
    if variant == "error" {
      failed = true
      message = "设备暂未响应，请稍后重试。"
    }
  }
  private func modelPreviewMacros() {
    inputs.macros = [MouseMacro(name: "复制选中内容", deviceKey: "preview", trigger: "button:4", enabled: true, steps: [MacroStep(keyCode: 8, down: true, flags: 1 << 20, delayMS: 0, label: "⌘C"), MacroStep(keyCode: 8, down: false, flags: 1 << 20, delayMS: 80, label: "⌘C")])]
  }
}
