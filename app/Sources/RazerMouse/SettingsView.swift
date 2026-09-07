// SPDX-License-Identifier: GPL-2.0-or-later
import RazerBindings
import SwiftUI

struct SettingsView: View {
  @ObservedObject var model: MouseModel
  @State private var tab: String
  @State private var x = ""
  @State private var y = ""
  @State private var independent = false
  @State private var dpiDraft: Double?
  @Environment(\.colorScheme) private var scheme

  init(model: MouseModel, tab: String = "performance") {
    self.model = model
    _tab = State(initialValue: tab)
  }
  private var lightingNames: [String] {
    model.info?.attributes.filter {
      $0.contains("brightness") || $0.contains("matrix_effect") || $0 == "charge_effect" || $0 == "charge_colour"
    } ?? []
  }
  private var wheelNames: [String] {
    ["scroll_mode", "scroll_acceleration", "scroll_smart_reel"].filter { model.has($0) }
  }
  private var receiverNames: [String] {
    model.info?.attributes.filter { $0.hasPrefix("hyperpolling_") } ?? []
  }
  private var sections: [(id: String, name: String, icon: String, detail: String)] {
    [("performance", "性能", "performance", "让每一次移动，恰到好处。")]
      + (model.has("device_idle_time") || model.has("charge_low_threshold") ? [("power", "电源", "power", "在响应速度与续航之间找到平衡。")]: [])
      + (lightingNames.isEmpty ? [] : [("lighting", "灯光", "light", "调整亮度、色彩与灯光效果。")])
      + (wheelNames.isEmpty && model.info?.tiltSupported != true ? [] : [("wheel", "滚轮", "wheel", "让滚动方式适应你的习惯。")])
      + (receiverNames.isEmpty ? [] : [("receiver", "接收器", "wireless", "管理无线连接与接收器。")])
      + [("macros", "按键与宏", "macro", "让重复的动作，一次完成。"), ("info", "设备信息", "info", "连接、固件与设备能力，一目了然。")]
  }
  var body: some View {
    HStack(spacing: 0) {
      sidebar
      Divider()
      VStack(alignment: .leading, spacing: 0) {
        HStack(alignment: .top) {
          VStack(alignment: .leading, spacing: 6) {
            Text(sections.first { $0.id == tab }?.name ?? "性能").font(.system(size: 27, weight: .semibold))
            Text(sections.first { $0.id == tab }?.detail ?? "").font(.system(size: 12)).foregroundStyle(.secondary)
          }
          Spacer()
          Button { model.panelPresented = true } label: {
            HStack(spacing: 6) { Glyph(name: "mouse", size: 14); Text("打开小组件") }
          }.buttonStyle(.bordered).controlSize(.large).help("在菜单栏直接调节鼠标")
        }.padding(.horizontal, 26).padding(.top, 24).padding(.bottom, 20)
        ScrollView {
          VStack(alignment: .leading, spacing: 16) {
            if tab == "macros" || tab == "info" {
              HStack(spacing: 9) {
                Glyph(name: "mouse", size: 18).foregroundStyle(MouseStyle.accent)
                Text(model.title).font(.system(size: 12, weight: .medium))
                Spacer()
                Text(model.batteryText).font(.system(size: 12, design: .rounded)).foregroundStyle(MouseStyle.accent)
              }.padding(14).background(MouseStyle.accent.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
            } else { deviceOverview }
            if model.accessDenied && tab != "macros" {
              Surface {
                ControlHeading(title: "允许访问鼠标", icon: "alert")
                Text("请在系统设置的输入监控中允许 Razer Mouse，然后重新打开应用。").foregroundStyle(.secondary)
                Button("打开输入监控设置") { model.openAccessSettings() }
              }
            } else if model.info != nil || tab == "macros" {
              Group {
                switch tab {
                case "power": power
                case "lighting": LightingView(model: model)
                case "wheel": controls(wheelNames)
                  if model.info?.tiltSupported == true { TiltView(input: model.inputs) }
                case "macros": MacroView(input: model.inputs)
                case "info": DeviceInfoView(model: model)
                case "receiver": controls(receiverNames)
                default: performance
                }
              }.disabled(tab != "macros" && tab != "info" && (model.busy || !model.connected || !model.responding))
            }
          }.padding(.horizontal, 26).padding(.bottom, 22)
        }.scrollIndicators(.hidden)
        feedback.padding(.horizontal, 26).padding(.vertical, 15)
      }.background(Color(nsColor: .windowBackgroundColor))
    }.frame(width: 900, height: 680).tint(MouseStyle.accent)
      .onAppear { syncFields() }
      .onChange(of: model.selected) { _, _ in syncFields(); tab = "performance" }
      .onChange(of: model.state?.dpi?.x) { _, _ in if dpiDraft == nil { syncFields() } }
      .onChange(of: model.operationRevision) { _, _ in syncFields() }
  }
  private var sidebar: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 9) {
        Glyph(name: "mouse", size: 25).foregroundStyle(MouseStyle.accent)
        VStack(alignment: .leading, spacing: 3) {
          Text("RAZER").font(.system(size: 14, weight: .bold)).tracking(3)
          Text("MOUSE CONTROL").font(.system(size: 8, weight: .medium)).tracking(1.5).foregroundStyle(.secondary)
        }
      }.padding(.top, 29).padding(.bottom, 35)
      Text("设备设置").font(.system(size: 10, weight: .medium)).foregroundStyle(.tertiary).padding(.bottom, 12)
      ForEach(sections, id: \.id) { item in
        Button { tab = item.id } label: {
          HStack(spacing: 11) {
            Glyph(name: item.icon, size: 17)
            Text(item.name).font(.system(size: 13, weight: tab == item.id ? .semibold : .regular))
            Spacer()
            if tab == item.id { Circle().fill(MouseStyle.accent).frame(width: 5, height: 5) }
          }.padding(.horizontal, 12).padding(.vertical, 5)
        }.buttonStyle(ControlButtonStyle(selected: tab == item.id)).padding(.bottom, 5)
      }
      Spacer()
      VStack(alignment: .leading, spacing: 7) {
        HStack(spacing: 6) {
          Circle().fill(model.connected && model.responding ? MouseStyle.accent : .orange).frame(width: 6, height: 6)
          Text(model.connected ? (model.responding ? "设备已连接" : "设备暂未响应") : "设备已断开")
        }.font(.system(size: 11, weight: .medium))
        Text("重新连接时保留设备设置").font(.system(size: 10)).foregroundStyle(.tertiary)
      }.padding(.bottom, 20)
    }.padding(.horizontal, 17).frame(width: 190).frame(maxHeight: .infinity)
      .background(.regularMaterial)
  }
  private var deviceOverview: some View {
    HStack(spacing: 18) {
      Image("mouse-art", bundle: .module).resizable().scaledToFit().frame(width: 49, height: 76).accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 8) {
        Text(model.title).font(.system(size: 16, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
        HStack(spacing: 7) {
          Glyph(name: model.info?.connection == "无线接收器" ? "wireless" : "usb", size: 12)
          Text(model.info?.connection ?? "等待连接")
          if let firmware = model.state?.firmware { Text("·"); Text(firmware) }
        }.font(.system(size: 11)).foregroundStyle(.secondary)
        if model.devices.count > 1 {
          Menu("切换设备") { ForEach(model.devices, id: \.id) { device in Button(device.name) { model.select(device.id) } } }
            .fixedSize().controlSize(.small)
        }
      }
      Spacer(minLength: 4)
      VStack(alignment: .trailing, spacing: 5) {
        Text(model.batteryText).font(.system(size: 26, weight: .medium, design: .rounded)).monospacedDigit()
          .foregroundStyle((model.state?.battery ?? 100) < 20 ? .orange : MouseStyle.accent)
        Text(!model.connected ? "上次读数" : model.state?.charging == true ? "正在充电" : "剩余电量")
          .font(.system(size: 10)).foregroundStyle(.secondary)
      }
    }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
      .background(MouseStyle.accent.opacity(scheme == .dark ? 0.08 : 0.055), in: RoundedRectangle(cornerRadius: 18))
      .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(MouseStyle.accent.opacity(0.12), lineWidth: 0.7))
  }
  private var performance: some View {
    VStack(spacing: 15) {
      if model.info?.cachedAttributes.contains("dpi") == true { Surface { LegacySettingsEditor(model: model) } }
      if model.has("dpi") {
        Surface {
          HStack {
            ControlHeading(title: "灵敏度", icon: "performance")
            Spacer()
            Toggle("独立 X / Y 轴", isOn: $independent).toggleStyle(.switch).controlSize(.mini).font(.system(size: 11))
          }
          HStack(alignment: .firstTextBaseline, spacing: 9) {
            TextField("未读取", text: $x).textFieldStyle(.plain).font(.system(size: 36, weight: .medium, design: .rounded))
              .monospacedDigit().frame(width: 150).accessibilityLabel("X 轴 DPI").onSubmit { applyDpi() }
            Text("DPI").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            if independent {
              Text("Y").foregroundStyle(.secondary)
              TextField("Y 轴", text: $y).frame(width: 90).textFieldStyle(.roundedBorder).accessibilityLabel("Y 轴 DPI").onSubmit { applyDpi() }
            }
            Spacer()
            Button("应用灵敏度") { applyDpi() }.buttonStyle(.borderedProminent).controlSize(.large)
          }
          if let device = model.info, device.maxDpi > device.minDpi, device.minDpi > 0, let current = model.state?.dpi {
            Slider(value: Binding(get: { dpiDraft ?? log2(Double(max(device.minDpi, min(device.maxDpi, current.x)))) }, set: {
              dpiDraft = $0
              x = String(DpiAdjustment.value(position: $0, minimum: device.minDpi, maximum: device.maxDpi, supported: device.dpiList))
            }), in: log2(Double(device.minDpi))...log2(Double(device.maxDpi)), onEditingChanged: { editing in
              if !editing { applyDpi(); dpiDraft = nil }
            }).accessibilityLabel("灵敏度调节，松开应用")
            HStack { Text("\(device.minDpi) DPI"); Spacer(); Text("\(device.maxDpi) DPI") }.font(.system(size: 10)).foregroundStyle(.tertiary)
          }
        }
      }
      if model.has("dpi_stages") {
        Surface {
          ControlHeading(title: "DPI 档位", icon: "edit")
          if let state = model.state {
            HStack(spacing: 7) {
              ForEach(Array(state.stages.enumerated()), id: \.offset) { index, stage in
                Button { model.stage(index) } label: {
                  VStack(spacing: 5) {
                    Text("档位 \(index + 1)").font(.system(size: 9))
                    Text("\(stage.x)").font(.system(size: 16, weight: .semibold, design: .rounded))
                  }
                }.buttonStyle(ControlButtonStyle(selected: state.activeStage == UInt32(index + 1) && state.dpi?.x == stage.x))
              }
            }
          }
          DisclosureGroup("编辑档位与预设") { StagePreferences(model: model) }.font(.system(size: 11)).foregroundStyle(.secondary)
        }
      }
      if model.has("poll_rate") {
        Surface {
          HStack { ControlHeading(title: "回报率", icon: "poll"); Spacer(); Text("更高回报率会增加耗电").font(.system(size: 10)).foregroundStyle(.tertiary) }
          LazyVGrid(columns: [GridItem(.adaptive(minimum: 74))], spacing: 8) {
            ForEach(model.info?.pollRates ?? [], id: \.self) { rate in
              Button { model.number("poll_rate", rate) } label: { Text("\(rate) Hz").font(.system(size: 11, weight: .medium, design: .rounded)) }
                .buttonStyle(ControlButtonStyle(selected: model.state?.pollRate == rate))
            }
          }
        }
      }
      if model.has("device_mode") { Surface { ControlRow(model: model, name: "device_mode") } }
    }
  }
  private var power: some View {
    VStack(spacing: 15) {
      if model.has("device_idle_time") { PowerAdjustment(model: model, name: "device_idle_time", title: "休眠等待", icon: "clock") }
      if model.has("charge_low_threshold") { PowerAdjustment(model: model, name: "charge_low_threshold", title: "低电量提醒", icon: "battery") }
    }
  }
  private func controls(_ names: [String]) -> some View {
    VStack(spacing: 12) { ForEach(names, id: \.self) { name in Surface { ControlRow(model: model, name: name) } } }
  }
  private var feedback: some View {
    HStack(spacing: 7) {
      if model.busy { ProgressView().controlSize(.mini) }
      else { Glyph(name: model.failed ? "alert" : model.message.isEmpty ? "check" : "check", size: 13).foregroundStyle(model.failed ? .orange : MouseStyle.accent) }
      Text(model.message.isEmpty ? (model.synapseRunning ? "雷云正在运行，请避免同时调整设置。" : "更改后自动读取设备，确认实际生效值。") : model.message)
        .font(.system(size: 10)).foregroundStyle(model.failed ? .orange : .secondary).lineLimit(2)
      Spacer()
      Button { model.refresh() } label: { Glyph(name: "refresh", size: 14) }.buttonStyle(.plain).help("刷新设备状态").accessibilityLabel("刷新设备状态").disabled(model.busy)
    }
  }
  private func syncFields() {
    x = model.state?.dpi.map { String($0.x) } ?? ""
    y = model.state?.dpi.map { String($0.y) } ?? ""
    dpiDraft = nil
  }
  private func applyDpi() {
    guard let xv = UInt32(x), let yv = UInt32(independent ? y : x) else { model.showErrorText("请输入有效 DPI"); syncFields(); return }
    model.perform { c, id in _ = try c.setDpi(id: id, x: xv, y: yv) }
  }
}

private struct StagePreferences: View {
  @ObservedObject var model: MouseModel
  @State private var name = ""
  @State private var presets = UserDefaults.standard.dictionary(forKey: "dpiPresets") as? [String: [String]] ?? [:]
  var body: some View {
    VStack(spacing: 12) {
      QuickStagesEditor(model: model)
      HStack {
        TextField("预设名称", text: $name).textFieldStyle(.roundedBorder)
        Button("保存当前档位") {
          guard let stages = model.state?.stages, !stages.isEmpty else { return }
          presets[name.trimmingCharacters(in: .whitespaces)] = stages.map { String($0.x) }
          UserDefaults.standard.set(presets, forKey: "dpiPresets"); name = ""
        }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        if !presets.isEmpty {
          Menu("应用预设") {
            ForEach(presets.keys.sorted(), id: \.self) { key in
              Button(key) {
                let values = (presets[key] ?? []).compactMap(UInt32.init)
                guard !values.isEmpty, values.count == presets[key]?.count, let active = model.state?.activeStage else { return }
                model.perform { c, id in try c.setStages(id: id, stages: values.map { DpiStage(x: $0, y: $0) }, active: min(active, UInt32(values.count))) }
              }
            }
          }.fixedSize()
        }
      }
    }.padding(.top, 10)
  }
}

private func title(_ name: String) -> String {
  let names = [
    "device_idle_time": "休眠等待", "charge_low_threshold": "低电量提醒", "scroll_mode": "自由滚动",
    "scroll_acceleration": "滚动加速", "scroll_smart_reel": "智能滚轮", "device_mode": "工作模式",
    "charge_effect": "充电灯光模式", "charge_colour": "充电灯光颜色",
    "hyperpolling_wireless_dongle_pair": "配对鼠标", "hyperpolling_wireless_dongle_unpair": "取消配对",
    "hyperpolling_wireless_dongle_indicator_led_mode": "接收器指示灯",
  ]
  if let value = names[name] { return value }
  let zone =
    name.hasPrefix("logo_")
    ? "标志"
    : name.hasPrefix("scroll_")
      ? "滚轮"
      : name.hasPrefix("left_")
        ? "左侧" : name.hasPrefix("right_") ? "右侧" : name.hasPrefix("backlight_") ? "背光" : "整体"
  let suffix = name.components(separatedBy: "_").last ?? ""
  let effects = [
    "brightness": "亮度", "static": "常亮", "spectrum": "光谱", "wave": "波浪", "reactive": "触发",
    "breath": "呼吸", "blinking": "闪烁", "none": "关闭", "on": "开启", "custom": "自定义",
  ]
  return zone + " · " + (effects[suffix] ?? "灯光")
}
private func rgb(_ color: Color) -> [UInt8] {
  let c = NSColor(color).usingColorSpace(.deviceRGB) ?? .green
  return [c.redComponent, c.greenComponent, c.blueComponent].map {
    UInt8(max(0, min(255, ($0 * 255).rounded())))
  }
}
struct ControlRow: View {
  @ObservedObject var model: MouseModel
  let name: String
  @State private var value = ""
  @State private var color = Color.green
  @State private var second = Color.blue
  @State private var mode = 0
  @State private var deviceMode: UInt8?
  @State private var speed = 1
  @State private var confirm = false
  private var isEffect: Bool { name.contains("matrix_effect") || name == "charge_colour" }
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(title(name)).font(.system(size: 12))
        Spacer()
        if name.contains("brightness") {
          TextField("0–255", text: $value).frame(width: 65).multilineTextAlignment(.trailing)
          Button("应用") { applyNumber() }
        } else if name == "device_mode" {
          Picker("工作模式", selection: $deviceMode) {
            Text("未读取").tag(Optional<UInt8>.none)
            Text("设备自主模式").tag(Optional<UInt8>.some(0))
            Text("软件控制模式").tag(Optional<UInt8>.some(3))
            if let deviceMode, ![0, 3].contains(deviceMode) {
              Text("模式 \(deviceMode)").tag(Optional.some(deviceMode))
            }
          }.labelsHidden().frame(width: 100)
          Button("应用") {
            guard let deviceMode else { return }
            model.perform(
              { c, id in
                try c.writeControl(id: id, name: name, payload: Data([deviceMode, 0]))
                let actual = try c.readControl(id: id, name: name)
                guard actual == Data([deviceMode, 0]) else {
                  throw NSError(domain: "RazerMouse", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "设备模式回读与请求不一致"])
                }
              },
              success: "已发送")
          }.disabled(deviceMode == nil)
        } else if isEffect {
          if name.hasSuffix("static") || name.hasSuffix("reactive") || name.hasSuffix("blinking")
            || name == "charge_colour"
          {
            ColorPicker("颜色", selection: $color, supportsOpacity: false).labelsHidden()
          }
          if name.hasSuffix("breath") {
            Picker("呼吸模式", selection: $mode) {
              Text("随机").tag(0)
              Text("单色").tag(1)
              Text("双色").tag(2)
            }.labelsHidden().frame(width: 90)
          }
          if name.hasSuffix("wave") {
            Picker("方向", selection: $speed) {
              Text("正向").tag(1)
              Text("反向").tag(2)
            }.labelsHidden().frame(width: 90)
          }
          if name.hasSuffix("reactive") {
            Picker("速度", selection: $speed) { ForEach(1...4, id: \.self) { Text("\($0)").tag($0) } }
              .labelsHidden().frame(width: 65)
          }
          Button("应用") { applyEffect() }
        } else if ["scroll_mode", "scroll_acceleration", "scroll_smart_reel"].contains(name) {
          if let actual = model.advancedNumber(name) {
            Toggle(
              "开关",
              isOn: Binding(
                get: { actual == 1 }, set: { model.number(name, $0 ? 1 : 0) })
            ).labelsHidden().toggleStyle(.switch).controlSize(.small)
          } else {
            Text("未读取").foregroundStyle(.secondary)
          }
        } else {
          TextField(
            name == "device_idle_time" ? "秒" : name == "charge_low_threshold" ? "%" : "数值",
            text: $value
          ).frame(width: 90).multilineTextAlignment(.trailing)
          Button(name.hasSuffix("unpair") ? "取消配对" : name.hasSuffix("pair") ? "配对" : "应用") {
            if name.hasSuffix("pair") { confirm = true } else { applyNumber() }
          }
        }
      }
      if name.hasSuffix("breath") && mode > 0 {
        HStack {
          ColorPicker("颜色 1", selection: $color, supportsOpacity: false)
          if mode == 2 { ColorPicker("颜色 2", selection: $second, supportsOpacity: false) }
        }.font(.caption)
      }
      if name == "device_mode" {
        Text("这是固件的工作状态，不是性能档位。普通调节通常无需切换，具体影响因型号而异。").font(.system(size: 10)).foregroundStyle(.secondary)
      }
      if name == "device_idle_time", let range = model.range(name) {
        Text("\(range.minimum)–\(range.maximum) 秒").font(.caption).foregroundStyle(.secondary)
      }
      if name == "charge_low_threshold" {
        Text(
          "当前 \(model.state?.lowBattery.map{String(Int((Double($0)*100/255).rounded()))} ?? "—")% · 范围由设备协议决定"
        ).font(.caption).foregroundStyle(.secondary)
      }
      if name.hasSuffix("pair") {
        Text("填写目标鼠标的产品 ID（十进制）。配对会改变接收器连接。").font(.caption).foregroundStyle(.secondary)
      }
    }
    .onAppear {
      if name == "device_idle_time" {
        value = model.state?.idleSeconds.map(String.init) ?? ""
      } else if name == "charge_low_threshold" {
        value =
          model.state?.lowBattery.map { String(Int((Double($0) * 100 / 255).rounded())) } ?? ""
      } else {
        model.readAdvanced([name])
      }
    }
    .onChange(of: model.operationRevision) { _, _ in
      if name == "device_idle_time" {
        value = model.state?.idleSeconds.map(String.init) ?? ""
      } else if name == "charge_low_threshold" {
        value =
          model.state?.lowBattery.map { String(Int((Double($0) * 100 / 255).rounded())) } ?? ""
      } else if let confirmed = model.advancedValues[name] {
        value = confirmed
      }
      if name == "device_mode" { deviceMode = model.advancedNumber(name).flatMap(UInt8.init(exactly:)) }
    }
    .onChange(of: model.selected) { _, _ in
      value = ""
      deviceMode = nil
      model.readAdvanced([name])
    }
    .onChange(of: model.advancedValues) { _, values in
      if let v = values[name] { value = v }
      if name == "device_mode" { deviceMode = values[name].flatMap(UInt8.init) }
    }
    .confirmationDialog(
      name.hasSuffix("unpair") ? "取消配对会断开这只鼠标" : "将接收器与目标鼠标配对", isPresented: $confirm,
      titleVisibility: .visible
    ) { Button("确认操作", role: .destructive) { applyNumber() } }
  }
  private func applyNumber() {
    guard let v = UInt32(value) else {
      model.showErrorText("请输入有效数值")
      return
    }
    if name == "charge_low_threshold" {
      guard v <= 100, let range = model.range(name) else {
        model.showErrorText("请输入有效百分比")
        return
      }
      let raw = UInt32((Double(v) * 255 / 100).rounded())
      guard (range.minimum...range.maximum).contains(raw) else {
        model.showErrorText(
          "设备支持 \(Int((Double(range.minimum) * 100 / 255).rounded()))–\(Int((Double(range.maximum) * 100 / 255).rounded()))%"
        )
        return
      }
      model.number(name, raw)
    } else {
      model.number(name, v)
    }
  }
  private func applyEffect() {
    let bytes: [UInt8]
    if name.hasSuffix("static") || name.hasSuffix("blinking") || name == "charge_colour" {
      bytes = rgb(color)
    } else if name.hasSuffix("reactive") {
      bytes = [UInt8(speed)] + rgb(color)
    } else if name.hasSuffix("breath") {
      bytes = mode == 0 ? [0] : mode == 1 ? rgb(color) : rgb(color) + rgb(second)
    } else if name.hasSuffix("wave") {
      bytes = Array(String(speed).utf8)
    } else {
      bytes = [48]
    }
    model.perform(
      { c, id in try c.writeControl(id: id, name: name, payload: Data(bytes)) }, success: "已发送")
  }
}
struct FrameEditor: View {
  @ObservedObject var model: MouseModel
  @State private var colors: [Color] = []
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 72))], spacing: 12) {
        ForEach(colors.indices, id: \.self) { i in
          ColorPicker("\(i+1)", selection: $colors[i], supportsOpacity: false).font(.caption)
        }
      }
      Button("应用逐灯颜色") {
        let count = colors.count
        guard count > 0 else { return }
        let values = colors.map(rgb)
        model.perform(
          { c, id in
            var start = 0
            while start < count {
              let end = min(count - 1, start + 19)
              let frame = [UInt8(0), UInt8(start), UInt8(end)] + values[start...end].flatMap { $0 }
              try c.writeControl(id: id, name: "matrix_custom_frame", payload: Data(frame))
              start = end + 1
            }
            try c.writeControl(id: id, name: "matrix_effect_custom", payload: Data([48]))
          }, success: "已发送")
      }
    }.onAppear { colors = Array(repeating: .green, count: Int(model.info?.ledCount ?? 0)) }
  }

}

struct LegacySettingsEditor: View {
  @ObservedObject var model: MouseModel
  @State private var dpi = ""
  @State private var poll: UInt32?
  @State private var logo: Bool?
  @State private var scroll: Bool?
  var body: some View {
    Section("完整配置") {
      Text("这款设备不能读取当前设置，部分命令会同时写入多项配置。请明确填写各项；成功只表示已发送。").font(.caption).foregroundStyle(
        .secondary)
      TextField("DPI", text: $dpi)
      Picker("回报率", selection: $poll) {
        Text("请选择").tag(Optional<UInt32>.none)
        ForEach(model.info?.pollRates ?? [], id: \.self) { Text("\($0) Hz").tag(Optional($0)) }
      }
      lightChoice("标志灯", selection: $logo)
      lightChoice("滚轮灯", selection: $scroll)
      Button("应用完整配置") {
        guard let dpi = UInt32(dpi), let poll, let logo, let scroll else { return }
        model.perform(
          { c, id in
            try c.configureLegacy(
              id: id,
              settings: LegacyConfiguration(
                dpi: dpi, pollRate: poll, logoOn: logo, scrollOn: scroll))
          }, success: "已发送 · 设备不支持硬件回读")
      }.disabled(UInt32(dpi) == nil || poll == nil || logo == nil || scroll == nil)
    }
  }
  private func lightChoice(_ title: String, selection: Binding<Bool?>) -> some View {
    Picker(title, selection: selection) {
      Text("请选择").tag(Optional<Bool>.none)
      Text("开").tag(Optional(true))
      Text("关").tag(Optional(false))
    }
  }
}
