// SPDX-License-Identifier: GPL-2.0-or-later
import AppKit
import RazerBindings
import SwiftUI

struct LightZone: Identifiable, Equatable {
  let prefix: String
  let name: String
  let brightness: String?
  let effects: [String]
  var id: String { prefix }
  static let labels = ["none": "关闭", "on": "开启", "static": "常亮", "spectrum": "光谱", "wave": "波浪", "reactive": "触发", "breath": "呼吸", "blinking": "闪烁", "custom": "逐灯颜色"]
  static func zones(_ device: DeviceInfo?) -> [LightZone] {
    guard let device else { return [] }
    let prefixes = Set(device.attributes.compactMap { name -> String? in
      guard let range = name.range(of: "matrix_effect_") else { return nil }
      return String(name[..<range.upperBound])
    })
    return prefixes.sorted().map { prefix in
      let stem = prefix.replacingOccurrences(of: "matrix_effect_", with: "")
      let name = ["": "整体", "logo_": "标志", "scroll_": "滚轮", "backlight_": "背光", "left_": "左侧", "right_": "右侧"][stem] ?? stem
      let brightness = stem.isEmpty ? "matrix_brightness" : stem + "led_brightness"
      return LightZone(prefix: prefix, name: name,
        brightness: device.attributes.contains(brightness) ? brightness : nil,
        effects: ["static", "spectrum", "breath", "wave", "reactive", "blinking", "on", "none", "custom"].filter { device.attributes.contains(prefix + $0) })
    }
  }
}

struct LightingWrite {
  let deviceID: String
  let deviceName: String
  let attribute: String
}

enum LightingPlan {
  static func writes(devices: [DeviceInfo], selected: String, zone: LightZone, effect: String, targets: Set<String>) -> [LightingWrite] {
    devices.flatMap { device -> [LightingWrite] in
      guard device.id == selected || targets.contains(device.id) else { return [] }
      let zones = LightZone.zones(device)
      return zones.filter { ($0.id == zone.id || device.id != selected) && $0.effects.contains(effect) }
        .map { LightingWrite(deviceID: device.id, deviceName: device.name, attribute: $0.prefix + effect) }
    }
  }
  static func payload(effect: String, color: [UInt8], second: [UInt8], mode: Int, speed: Int) -> Data {
    switch effect {
    case "static", "blinking": return Data(color)
    case "reactive": return Data([UInt8(clamping: speed)] + color)
    case "breath": return Data(mode == 0 ? [0] : mode == 1 ? color : color + second)
    case "wave": return Data(String(speed).utf8)
    default: return Data("1".utf8)
    }
  }
}

struct LightingView: View {
  @ObservedObject var model: MouseModel
  var compact = false
  @State private var zoneID = ""
  @State private var effect = ""
  @State private var color = Color(red: 0.1, green: 0.8, blue: 0.5)
  @State private var second = Color.blue
  @State private var mode = 1
  @State private var speed = 1
  @State private var brightness: Double?
  @State private var targets: Set<String> = []
  private var zones: [LightZone] { LightZone.zones(model.info) }
  private var zone: LightZone? { zones.first { $0.id == zoneID } ?? zones.max { $0.effects.count < $1.effects.count } }
  private var chosenEffect: String { zone?.effects.contains(effect) == true ? effect : zone?.effects.first ?? "" }
  private var otherDevices: [DeviceInfo] { model.devices.filter { $0.id != model.selected && !LightZone.zones($0).isEmpty } }
  var body: some View {
    VStack(spacing: 13) {
      Surface {
        HStack {
          ControlHeading(title: "灯区", icon: "light")
          Spacer()
          Picker("选择灯区", selection: Binding(get: { zone?.id ?? "" }, set: { zoneID = $0; brightness = nil; readBrightness() })) {
            ForEach(zones) { zone in Text(zone.name).tag(zone.id) }
          }.labelsHidden().fixedSize()
        }
        if let attribute = zone?.brightness {
          HStack {
            Text("亮度").font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer()
            Text(model.advancedNumber(attribute).map { "\(Int((brightness ?? Double($0)) * 100 / 255))%" } ?? "未读取")
              .font(.system(size: 22, weight: .medium, design: .rounded)).monospacedDigit()
          }
          if let actual = model.advancedNumber(attribute) {
            Slider(value: Binding(get: { brightness ?? Double(actual) }, set: { brightness = $0 }), in: 0...255, onEditingChanged: { editing in
              if !editing, let brightness { model.number(attribute, UInt32(brightness.rounded())); self.brightness = nil }
            }).accessibilityLabel("灯区亮度，松开应用")
          } else { Button("读取亮度") { readBrightness() }.controlSize(.small) }
        }
      }
      if let zone {
        Surface {
          HStack { ControlHeading(title: "效果方案", icon: "settings"); Spacer(); Text("应用后生效").font(.system(size: 10)).foregroundStyle(.secondary) }
          LazyVGrid(columns: [GridItem(.adaptive(minimum: compact ? 80 : 90))], spacing: 7) {
            ForEach(zone.effects, id: \.self) { item in
              Button { effect = item } label: { Text(LightZone.labels[item] ?? item).font(.system(size: 11, weight: .medium)) }
                .buttonStyle(ControlButtonStyle(selected: chosenEffect == item))
            }
          }
          if ["static", "reactive", "blinking"].contains(chosenEffect) || chosenEffect == "breath" && mode > 0 {
            HStack {
              ColorPicker("颜色", selection: $color, supportsOpacity: false)
              if chosenEffect == "breath" && mode == 2 { ColorPicker("第二种颜色", selection: $second, supportsOpacity: false) }
            }.font(.system(size: 11))
          }
          if chosenEffect == "breath" {
            Picker("呼吸方式", selection: $mode) { Text("随机").tag(0); Text("单色").tag(1); Text("双色").tag(2) }.pickerStyle(.segmented)
          }
          if chosenEffect == "wave" {
            Picker("方向", selection: $speed) { Text("正向").tag(1); Text("反向").tag(2) }.pickerStyle(.segmented)
          }
          if chosenEffect == "reactive" {
            Picker("响应速度", selection: $speed) { ForEach(1...4, id: \.self) { Text("\($0)").tag($0) } }
          }
          if chosenEffect == "custom", model.has("matrix_custom_frame") {
            FrameEditor(model: model)
            Text("逐灯颜色按当前设备布局发送。").font(.system(size: 10)).foregroundStyle(.secondary)
          } else {
            Button { apply(zone) } label: {
              HStack { Glyph(name: "check", size: 14); Text(targets.isEmpty ? "应用到\(zone.name)" : "应用并同步") }
            }.buttonStyle(ControlButtonStyle(selected: true)).disabled(model.busy || !model.connected || !model.responding)
          }
        }
      }
      if !otherDevices.isEmpty, chosenEffect != "custom" {
        Surface {
          ControlHeading(title: "同步到其他设备", icon: "wireless")
          ForEach(otherDevices, id: \.id) { device in
            Toggle(device.name, isOn: Binding(get: { targets.contains(device.id) }, set: { if $0 { targets.insert(device.id) } else { targets.remove(device.id) } }))
              .toggleStyle(.switch).controlSize(.small).font(.system(size: 11))
          }
          Text("点击应用时同步到所选设备的兼容灯区；不支持的效果跳过。重新连接不会自动写入。").font(.system(size: 10)).foregroundStyle(.secondary)
        }
      }
      if model.has("charge_effect") || model.has("charge_colour") {
        Surface {
          ControlHeading(title: "充电灯光", icon: "power")
          if model.has("charge_effect") { ControlRow(model: model, name: "charge_effect") }
          if model.has("charge_colour") { ControlRow(model: model, name: "charge_colour") }
        }
      }
    }.onAppear { readBrightness() }
      .onChange(of: model.selected) { _, _ in zoneID = ""; effect = ""; targets = []; brightness = nil; readBrightness() }
      .onChange(of: model.operationRevision) { _, _ in brightness = nil }
      .onChange(of: model.devices.map(\.id)) { _, ids in targets.formIntersection(Set(ids)) }
      .onChange(of: chosenEffect) { _, _ in speed = 1 }
  }
  private func readBrightness() { model.readAdvanced([zone?.brightness].compactMap { $0 }) }
  private func apply(_ zone: LightZone) {
    let payload = LightingPlan.payload(effect: chosenEffect, color: components(color), second: components(second), mode: mode, speed: speed)
    let writes = LightingPlan.writes(devices: model.devices, selected: model.selected, zone: zone, effect: chosenEffect, targets: targets)
    model.applyLighting(writes, payload: payload, requested: targets.count + 1)
  }
  private func components(_ color: Color) -> [UInt8] {
    let c = NSColor(color).usingColorSpace(.deviceRGB) ?? .green
    return [c.redComponent, c.greenComponent, c.blueComponent].map { UInt8(clamping: Int(($0 * 255).rounded())) }
  }
}
