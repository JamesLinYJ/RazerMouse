// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

struct PowerAdjustment: View {
  @ObservedObject var model: MouseModel
  let name: String
  let title: String
  let icon: String
  @State private var draft: Double?
  @State private var text = ""
  private var percentage: Bool { name == "charge_low_threshold" }
  private var confirmed: UInt32? { percentage ? model.state?.lowBattery : model.state?.idleSeconds }
  private func displayed(_ raw: Double) -> Double { percentage ? raw * 100 / 255 : raw }
  var body: some View {
    Surface {
      ControlHeading(title: title, icon: icon)
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        TextField("未读取", text: $text).font(.system(size: 26, weight: .medium, design: .rounded))
          .textFieldStyle(.plain).monospacedDigit().onSubmit { applyText() }.accessibilityLabel(
            title)
        Text(percentage ? "%" : "秒").font(.system(size: 11)).foregroundStyle(.secondary)
        Spacer()
        Button("应用") { applyText() }.controlSize(.small)
      }
      if let range = model.range(name), let confirmed {
        Slider(
          value: Binding(
            get: {
              min(Double(range.maximum), max(Double(range.minimum), draft ?? Double(confirmed)))
            },
            set: { value in
              draft = value
              text = String(Int(displayed(value).rounded()))
            }),
          in: Double(range.minimum)...Double(range.maximum),
          onEditingChanged: { editing in
            if !editing, let draft {
              model.number(name, UInt32(draft.rounded()))
              self.draft = nil
            }
          }
        ).controlSize(.small).accessibilityLabel("调节" + title + "，松开应用")
        HStack {
          Text("\(Int(displayed(Double(range.minimum)).rounded()))\(percentage ? "%" : " 秒")")
          Spacer()
          Text("\(Int(displayed(Double(range.maximum)).rounded()))\(percentage ? "%" : " 秒")")
        }.font(.system(size: 9, design: .rounded)).foregroundStyle(.secondary)
        if confirmed < range.minimum || confirmed > range.maximum {
          Text("当前值超出可设置范围，调整后才会更改。")
            .font(.system(size: 10)).foregroundStyle(.orange)
        }
      }
    }.onAppear { sync() }
      .onChange(of: model.operationRevision) { _, _ in sync() }
      .onChange(of: model.selected) { _, _ in sync() }
      .onChange(of: confirmed) { _, _ in if draft == nil { sync() } }
  }
  private func sync() {
    draft = nil
    text = confirmed.map { String(Int(displayed(Double($0)).rounded())) } ?? ""
  }
  private func applyText() {
    guard let value = Double(text), value.isFinite, value >= 0,
      value <= (percentage ? 100 : Double(UInt32.max)), let range = model.range(name)
    else {
      model.showErrorText("请输入有效数值")
      sync()
      return
    }
    guard let rawValue = PowerAdjustmentValue.raw(displayed: value, percentage: percentage,
      minimum: range.minimum, maximum: range.maximum) else {
      model.showErrorText("数值超出设备支持的范围")
      sync()
      return
    }
    model.number(name, rawValue)
  }
}
