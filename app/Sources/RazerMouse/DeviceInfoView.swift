// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI
struct DeviceInfoView: View {
  @ObservedObject var model: MouseModel
  var body: some View {
    VStack(spacing: 15) {
      Surface {
        ControlHeading(title: "设备身份", icon: "info")
        row("名称", model.title)
        row("连接方式", model.info?.connection ?? "未连接")
        row("产品 ID", model.info.map { String(format: "0x%04X", $0.pid) } ?? "未读取")
        row("固件版本", model.state?.firmware ?? "未读取")
        row("序列号", model.advancedValues["device_serial"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "未读取")
        Button("重新读取设备信息") { model.refresh(); model.readAdvanced(["device_serial"]) }.controlSize(.small).disabled(model.busy || !model.connected)
      }
      Surface {
        ControlHeading(title: "能力概览", icon: "performance")
        if let device = model.info {
          row("DPI 范围", "\(device.minDpi)–\(device.maxDpi)")
          row("回报率", device.pollRates.map { "\($0)" }.joined(separator: " / ") + " Hz")
          row("灯区", LightZone.zones(device).map(\.name).joined(separator: "、").isEmpty ? "无灯光控制" : LightZone.zones(device).map(\.name).joined(separator: "、"))
          row("滚轮倾斜扩展", device.tiltSupported ? "上游已描述此型号" : "此型号未提供")
        }
        Text("功能入口按设备能力显示。序列号仅在本机读取，不上传。").font(.system(size: 11)).foregroundStyle(.secondary)
      }
    }.onAppear { model.readAdvanced(["device_serial"]) }
  }
  private func row(_ title: String, _ value: String) -> some View {
    HStack(alignment: .top) { Text(title).foregroundStyle(.secondary).frame(width: 88, alignment: .leading); Text(value).textSelection(.enabled); Spacer(minLength: 0) }.font(.system(size: 12)).padding(.vertical, 4)
  }
}
