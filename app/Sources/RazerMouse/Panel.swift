// SPDX-License-Identifier: GPL-2.0-or-later
import AppKit
import RazerBindings
import SwiftUI

struct Surface<Content: View>: View {
  @ViewBuilder var content: Content
  @Environment(\.colorScheme) private var scheme
  var body: some View {
    VStack(alignment: .leading, spacing: 12) { content }
      .padding(15).frame(maxWidth: .infinity, alignment: .leading)
      .background {
        RoundedRectangle(cornerRadius: MouseStyle.radius).fill(
          scheme == .dark ? Color.white.opacity(0.045) : Color.white.opacity(0.92))
      }
      .overlay(
        RoundedRectangle(cornerRadius: MouseStyle.radius)
          .strokeBorder(
            scheme == .dark ? Color.white.opacity(0.075) : .black.opacity(0.045), lineWidth: 0.7)
      )
      .shadow(color: .black.opacity(scheme == .dark ? 0.07 : 0.025), radius: 5, y: 2)
  }
}

struct Panel: View {
  @ObservedObject var model: MouseModel
  @Environment(\.colorScheme) private var scheme
  @State private var section = "常用"
  @State private var editingStages = false
  @State private var dpiDraft: Double?

  init(model: MouseModel, section: String = "常用", editingStages: Bool = false) {
    self.model = model
    _section = State(initialValue: section)
    _editingStages = State(initialValue: editingStages)
  }
  private var sections: [(name: String, icon: String)] {
    [("常用", "performance")]
      + (model.has("device_idle_time") || model.has("charge_low_threshold")
        ? [("电源", "power")] : [])
      + (!LightZone.zones(model.info).isEmpty ? [("灯光", "light")] : [])
      + (wheelControls.isEmpty && model.info?.tiltSupported != true ? [] : [("滚轮", "wheel")])
  }
  private var wheelControls: [String] {
    ["scroll_mode", "scroll_acceleration", "scroll_smart_reel"].filter { model.has($0) }
  }
  private var available: Bool { model.connected && model.responding }
  var body: some View {
    VStack(spacing: 13) {
      header
      if model.info != nil {
        if !available || !model.connectionNotice.isEmpty { connectionBanner }
        navigation
        ScrollView {
          VStack(spacing: 11) {
            if section == "常用" {
              if model.has("dpi") { performance }
              if model.has("poll_rate") { polling }
            }
            if section == "电源" {
              if model.has("device_idle_time") {
                PowerAdjustment(
                  model: model, name: "device_idle_time", title: "休眠等待", icon: "clock")
              }
              if model.has("charge_low_threshold") {
                PowerAdjustment(
                  model: model, name: "charge_low_threshold", title: "低电量提醒", icon: "battery")
              }
            }
            if section == "灯光" { LightingView(model: model, compact: true) }
            if section == "滚轮" {
              Surface {
                ControlHeading(title: "滚轮调节", icon: "wheel")
                ForEach(wheelControls, id: \.self) { ControlRow(model: model, name: $0) }
                }
                if model.info?.tiltSupported == true { TiltView(input: model.inputs)
              }
            }
          }.padding(1)
        // A popover asks for an ideal height. A maximum alone allows ScrollView
        // to propose zero and hide every control in the real MenuBarExtra host.
        }.scrollIndicators(.hidden).frame(height: editingStages ? 430 : 350)
          .disabled(!available || model.busy)
      } else {
        emptyState
      }
      if !model.message.isEmpty { feedback }
      if model.synapseRunning {
        HStack(alignment: .top, spacing: 6) {
          Glyph(name: "alert", size: 12)
          Text("雷云正在运行，请避免同时调整设置。")
        }.font(.system(size: 10)).foregroundStyle(.secondary)
      }
      footer
    }.padding(17).frame(width: 360)
      .background {
        // An opaque base is retained beneath every section, including header and footer.
        ZStack {
          Color(nsColor: .windowBackgroundColor)
          LinearGradient(
            colors: [MouseStyle.accent.opacity(scheme == .dark ? 0.045 : 0.025), .clear],
            startPoint: .topLeading, endPoint: .bottomTrailing)
        }.ignoresSafeArea()
      }.tint(MouseStyle.accent)
      .onAppear {
        model.refresh()
        readQuickControls()
      }
      .onChange(of: model.selected) { _, _ in
        dpiDraft = nil
        editingStages = false
        section = "常用"
        readQuickControls()
      }
      .onChange(of: model.operationRevision) { _, _ in
        dpiDraft = nil
      }
  }
  private var header: some View {
    VStack(alignment: .leading, spacing: 15) {
      HStack(spacing: 7) {
        Glyph(name: "mouse", size: 19).foregroundStyle(MouseStyle.accent)
        Text("RAZER MOUSE").font(.system(size: 9, weight: .semibold)).tracking(1.6)
          .foregroundStyle(.secondary)
        Spacer()
        if model.devices.count > 1 {
          Menu {
            ForEach(model.devices, id: \.id) { device in
              Button(device.name) { model.select(device.id) }
            }
          } label: {
            Glyph(name: "settings", size: 15)
          }
          .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 24).accessibilityLabel(
            "切换鼠标")
        }
        HStack(spacing: 4) {
          Glyph(name: model.info?.connection == "USB" ? "usb" : "wireless", size: 11)
          Text(available ? model.info?.connection ?? "已连接" : "离线")
        }.font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
          .padding(.horizontal, 8).padding(.vertical, 5)
          .background(.primary.opacity(0.045), in: Capsule())
      }
      HStack(alignment: .center, spacing: 12) {
        VStack(alignment: .leading, spacing: 10) {
          Text(model.title).font(.system(size: 17, weight: .semibold)).lineLimit(2)
            .fixedSize(horizontal: false, vertical: true).help(model.title)
          HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(model.batteryText).font(.system(size: 28, weight: .medium, design: .rounded))
              .monospacedDigit().foregroundStyle(model.batteryColor)
            Text(!available ? "上次读数" : model.state?.charging == true ? "正在充电" : "剩余电量")
              .font(.system(size: 10)).foregroundStyle(.secondary)
          }
          GeometryReader { geometry in
            ZStack(alignment: .leading) {
              Capsule().fill(.primary.opacity(0.07))
              Capsule().fill(model.batteryColor)
                .frame(width: geometry.size.width * CGFloat(model.state?.battery ?? 0) / 100)
            }
          }.frame(height: 3).accessibilityHidden(true)
        }
        Image("mouse-art", bundle: .module).resizable().scaledToFit()
          .frame(width: 58, height: 88).rotationEffect(.degrees(8)).opacity(available ? 1 : 0.4)
          .padding(.horizontal, 7).accessibilityHidden(true)
      }
    }.padding(.horizontal, 3).padding(.top, 2).padding(.bottom, 4)
  }
  private var navigation: some View {
    HStack(spacing: 4) {
      ForEach(sections, id: \.name) { item in
        Button {
          section = item.name
          readQuickControls()
        } label: {
          HStack(spacing: 5) {
            Glyph(name: item.icon, size: 13)
            Text(item.name).font(.system(size: 11, weight: .medium))
          }
        }.buttonStyle(ControlButtonStyle(selected: section == item.name))
          .accessibilityAddTraits(section == item.name ? .isSelected : [])
      }
    }.padding(4).background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 13))
  }
  private var performance: some View {
    Surface {
      HStack {
        ControlHeading(title: "灵敏度", icon: "performance")
        Spacer()
        Text("DPI").font(.system(size: 9, weight: .semibold)).tracking(1).foregroundStyle(.tertiary)
      }
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        TextField("未读取", text: $model.dpiText).font(
          .system(size: 31, weight: .medium, design: .rounded)
        )
        .monospacedDigit().textFieldStyle(.plain).onSubmit { model.setDpi() }
        .accessibilityLabel("当前 DPI 数值")
        Button {
          model.setDpi()
        } label: {
          HStack(spacing: 4) {
            Text("应用")
            Glyph(name: "arrow", size: 12)
          }
          .font(.system(size: 10, weight: .semibold))
          .padding(.horizontal, 10).padding(.vertical, 7)
          .background(MouseStyle.accent.opacity(0.11), in: Capsule())
        }.buttonStyle(.plain).foregroundStyle(MouseStyle.accent).accessibilityLabel("应用 DPI")
      }
      if let device = model.info, let current = model.state?.dpi?.x, device.minDpi > 0,
        device.maxDpi > device.minDpi
      {
        VStack(spacing: 2) {
          Slider(
            value: Binding(
              get: { dpiDraft ?? log2(Double(max(device.minDpi, min(current, device.maxDpi)))) },
              set: { position in
                dpiDraft = position
                model.dpiText = String(
                  DpiAdjustment.value(
                    position: position, minimum: device.minDpi,
                    maximum: device.maxDpi, supported: device.dpiList))
              }), in: log2(Double(device.minDpi))...log2(Double(device.maxDpi)),
            onEditingChanged: { dragging in
              if !dragging, dpiDraft != nil {
                model.setDpi()
                dpiDraft = nil
              }
            }
          ).controlSize(.small).accessibilityLabel("调节 DPI，松开应用")
          HStack {
            Text(device.minDpi.formatted())
            Spacer()
            Text("拖动调节").foregroundStyle(.tertiary)
            Spacer()
            Text(device.maxDpi.formatted())
          }.font(.system(size: 9, design: .rounded)).foregroundStyle(.secondary)
        }
      }
      if let state = model.state, !state.stages.isEmpty {
        HStack(spacing: 5) {
          ForEach(Array(state.stages.enumerated()), id: \.offset) { index, stage in
            Button {
              model.stage(index)
            } label: {
              Text(stage.x.formatted(.number.grouping(.never)))
                .font(.system(size: 10, weight: .semibold, design: .rounded)).monospacedDigit()
            }.buttonStyle(
              ControlButtonStyle(
                selected: state.activeStage == UInt32(index + 1) && state.dpi?.x == stage.x)
            )
            .accessibilityLabel("DPI 档位 \(index + 1)，\(stage.x)")
          }
        }
      }
      if model.has("dpi_stages") {
        DisclosureGroup(isExpanded: $editingStages) {
          QuickStagesEditor(model: model).padding(.top, 8)
        } label: {
          HStack(spacing: 5) {
            Glyph(name: "edit", size: 11)
            Text("编辑档位")
          }
          .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
        }
      }
    }
  }
  private var polling: some View {
    Surface {
      HStack {
        ControlHeading(title: "回报率", icon: "poll")
        Spacer()
        if let rate = model.state?.pollRate, rate > 0 {
          Text(String(format: "%.2f ms", 1000 / Double(rate)))
            .font(.system(size: 10, design: .rounded)).foregroundStyle(.secondary)
            .help("每次报告的理论间隔")
        } else {
          Text("未读取").font(.caption).foregroundStyle(.secondary)
        }
      }
      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 3), spacing: 5)
      {
        ForEach(model.info?.pollRates ?? [], id: \.self) { rate in
          Button {
            model.number("poll_rate", rate)
          } label: {
            Text("\(rate.formatted(.number.grouping(.never))) Hz").font(
              .system(size: 10, weight: .medium, design: .rounded))
          }.buttonStyle(ControlButtonStyle(selected: model.state?.pollRate == rate))
            .disabled(model.state?.pollRate == nil)
        }
      }
    }
  }
  private var brightnessZone: String? {
    [
      "matrix_brightness", "logo_led_brightness", "backlight_led_brightness",
      "scroll_led_brightness",
    ].first { model.has($0) }
  }
  private func readQuickControls() {
    model.readAdvanced([brightnessZone].compactMap { $0 } + wheelControls)
  }
  private var connectionBanner: some View {
    HStack(spacing: 7) {
      Glyph(name: available ? "check" : "disconnected", size: 14)
      Text(model.connectionNotice.isEmpty ? model.statusLabel : model.connectionNotice)
        .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 0)
    }.font(.system(size: 10)).foregroundStyle(available ? MouseStyle.accent : .orange)
      .padding(10).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
  }
  private var feedback: some View {
    HStack(alignment: .top, spacing: 7) {
      if model.busy {
        ProgressView().controlSize(.mini)
      } else {
        Glyph(name: model.failed ? "alert" : "check", size: 14)
      }
      Text(model.message).font(.system(size: 10)).lineLimit(3).fixedSize(
        horizontal: false, vertical: true)
      Spacer(minLength: 0)
      if model.failed {
        Button("重试读取") { model.refresh() }.font(.system(size: 10)).buttonStyle(.plain)
      }
    }.foregroundStyle(model.failed ? Color.orange : MouseStyle.accent).padding(10)
      .background(
        (model.failed ? Color.orange : MouseStyle.accent).opacity(0.065),
        in: RoundedRectangle(cornerRadius: 10))
  }
  private var emptyState: some View {
    VStack(spacing: 13) {
      Glyph(name: "mouse", size: 38).foregroundStyle(MouseStyle.accent.opacity(0.6))
      Text(model.accessDenied ? "允许访问鼠标" : "连接你的鼠标").font(.system(size: 15, weight: .medium))
      Text(model.accessDenied ? "请在 macOS 输入监控中允许 Razer Mouse。" : "连接 USB 或无线接收器，\n可用的控制将自动出现。")
        .font(.system(size: 11)).multilineTextAlignment(.center).foregroundStyle(.secondary)
      if model.accessDenied { Button("打开输入监控设置") { model.openAccessSettings() } }
    }.frame(maxWidth: .infinity).padding(.vertical, 30)
  }
  private var footer: some View {
    HStack(spacing: 8) {
      Button {
        model.refresh()
        model.scan()
      } label: {
        Glyph(name: "refresh", size: 14)
      }
      .buttonStyle(.plain).disabled(model.busy).accessibilityLabel("刷新设备状态")
      if model.busy {
        Text("正在同步").font(.system(size: 9))
      } else if let updated = model.lastUpdated {
        Text(updated, format: .dateTime.hour().minute()).font(.system(size: 9, design: .rounded))
          .help("最近一次读取时间")
      }
      Spacer()
      Button {
        model.openSettings()
      } label: {
        HStack(spacing: 5) {
          Glyph(name: "settings", size: 13)
          Text("详细设置").font(.system(size: 10, weight: .medium))
        }
      }.buttonStyle(.plain)
      Menu {
        Button("退出 Razer Mouse") { NSApp.terminate(nil) }
      } label: {
        Glyph(name: "more", size: 15).foregroundStyle(scheme == .dark ? Color.white : Color.black)
      }
      .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 25).accessibilityLabel(
        "更多操作")
    }.foregroundStyle(.secondary).padding(.horizontal, 3).padding(.top, 2)
  }
}
struct QuickStagesEditor: View {
  @ObservedObject var model: MouseModel
  @State private var values: [String] = []
  var body: some View {
    VStack(spacing: 10) {
      ForEach(values.indices, id: \.self) { index in
        HStack {
          Text("档位 \(index + 1)").foregroundStyle(.secondary)
          Spacer()
          TextField("DPI", text: $values[index]).multilineTextAlignment(.trailing)
            .frame(width: 90).textFieldStyle(.roundedBorder)
            .accessibilityLabel("编辑档位 \(index + 1) DPI")
          Button {
            values.remove(at: index)
          } label: {
            Glyph(name: "minus", size: 14)
          }
          .buttonStyle(.plain).disabled(values.count <= 1).accessibilityLabel("移除档位 \(index + 1)")
        }
      }
      HStack {
        Button("添加档位") { values.append("") }
          .disabled(values.count >= Int(model.info?.maxStages ?? 0))
        Spacer()
        Button("保存档位") {
          let numbers = values.compactMap(UInt32.init)
          guard numbers.count == values.count, !numbers.isEmpty,
            let active = model.state?.activeStage
          else {
            model.showErrorText("请填写有效 DPI 并先读取当前档位")
            return
          }
          model.perform { controller, id in
            try controller.setStages(
              id: id, stages: numbers.map { DpiStage(x: $0, y: $0) },
              active: min(active, UInt32(numbers.count)))
          }
        }.buttonStyle(.borderedProminent)
      }.controlSize(.small)
    }.onAppear { sync() }
      .onChange(of: model.operationRevision) { _, _ in sync() }
      .onChange(of: model.selected) { _, _ in sync() }
  }
  private func sync() { values = model.state?.stages.map { String($0.x) } ?? [] }
}
