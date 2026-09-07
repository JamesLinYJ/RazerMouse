// SPDX-License-Identifier: GPL-2.0-or-later
import AppKit
import SwiftUI

struct MacroView: View {
  @ObservedObject var input: InputActions
  @State private var draft = MouseMacro()
  @State private var recording = false
  @State private var deleteID: UUID?
  var body: some View {
    VStack(spacing: 15) {
      Surface {
        HStack {
          ControlHeading(title: "按键动作", icon: "macro")
          Spacer()
          Toggle("启用已绑定的宏", isOn: $input.macrosEnabled).toggleStyle(.switch).controlSize(.small)
            .disabled(!input.monitoring || !input.accessReady || recording)
        }
        HStack(spacing: 10) {
          Button(input.monitoring ? "停止监听" : "监听当前鼠标") { if input.monitoring { input.stopMonitoring() } else { input.startMonitoring() } }
          Button("允许辅助功能") { input.requestAccess() }
          Button("停止执行") { input.stopPlayback() }.disabled(input.playing == nil)
          Spacer()
        }.controlSize(.small)
        Text(input.status).font(.system(size: 11)).foregroundStyle(.secondary).textSelection(.enabled)
        Text("绑定在本机执行，原生按键动作仍会保留。切换接收应用、断开或休眠会停止执行；重新连接后需手动启用。").font(.system(size: 10)).foregroundStyle(.secondary)
      }
      Surface {
        HStack {
          ControlHeading(title: "动作编辑器", icon: "macro")
          Spacer()
          if !input.macros.isEmpty {
            Menu("我的宏 · \(input.macros.count)") {
              ForEach(input.macros) { macro in Button(macro.name) { recording = false; draft = macro } }
            }.fixedSize().controlSize(.small)
          }
          Button("新建") { recording = false; draft = MouseMacro() }.controlSize(.small)
        }
        TextField("为这组动作取一个名字", text: $draft.name).font(.system(size: 19, weight: .medium)).textFieldStyle(.plain).accessibilityLabel("宏名称")
        HStack {
          Button(recording ? "结束录制" : "录制按键") {
            if !recording { draft.steps = []; input.macrosEnabled = false; input.stopPlayback() }
            recording.toggle()
          }.buttonStyle(.borderedProminent)
          Button("识别鼠标按键") { recording = false; input.learn() }.disabled(!input.monitoring || recording)
          Spacer()
          Text(draft.trigger.isEmpty ? "尚未绑定" : MouseInputReport.label(draft.trigger)).font(.system(size: 11)).foregroundStyle(.secondary)
        }
        if recording {
          KeyboardCapture(steps: $draft.steps, recording: $recording)
            .frame(height: 74)
            .background(MouseStyle.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
            .overlay(VStack(spacing: 5) { Text("正在录制…").font(.system(size: 14, weight: .semibold)); Text("输入按键组合，Esc 结束；最多 60 秒").font(.system(size: 10)) }.foregroundStyle(MouseStyle.accent).allowsHitTesting(false))
        }
        if draft.steps.isEmpty && !recording {
          VStack(spacing: 9) {
            Glyph(name: "macro", size: 30).foregroundStyle(MouseStyle.accent.opacity(0.7))
            Text("把重复操作，变成一次按下").font(.system(size: 14, weight: .medium))
            Text("录制快捷键与按键间隔，再绑定到鼠标按键。").font(.system(size: 11)).foregroundStyle(.secondary)
          }.frame(maxWidth: .infinity).padding(.vertical, 26)
        } else if !recording {
          ScrollView {
            VStack(spacing: 6) {
              ForEach($draft.steps) { $step in
                HStack(spacing: 9) {
                  Text(step.down ? "按下" : "松开").font(.system(size: 10)).foregroundStyle(.secondary).frame(width: 30)
                  Text(step.label).font(.system(size: 12, weight: .medium, design: .monospaced)).frame(maxWidth: .infinity, alignment: .leading)
                  TextField("间隔", value: $step.delayMS, format: .number).textFieldStyle(.roundedBorder).frame(width: 65).accessibilityLabel("动作前等待毫秒")
                  Text("ms").font(.system(size: 10)).foregroundStyle(.secondary)
                  Button { draft.steps.removeAll { $0.id == step.id } } label: { Glyph(name: "minus", size: 12) }.buttonStyle(.plain).accessibilityLabel("移除此动作")
                }.padding(8).background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 8))
              }
            }
          }.frame(height: min(200, max(60, CGFloat(draft.steps.count) * 36)))
        }
        HStack {
          if input.macros.contains(where: { $0.id == draft.id }) {
            Button { deleteID = draft.id } label: { Glyph(name: "minus", size: 14) }.help("删除这个宏").accessibilityLabel("删除这个宏")
          }
          Toggle("启用此绑定", isOn: $draft.enabled).toggleStyle(.switch).controlSize(.small)
          Spacer()
          Button("3 秒后试运行") { input.test(draft) }.disabled(recording || draft.steps.isEmpty || !input.accessReady)
          Button("保存宏") { _ = input.save(draft) }.buttonStyle(.borderedProminent).disabled(recording || draft.steps.isEmpty)
        }.font(.system(size: 11))
      }
    }.onAppear { if let first = input.macros.first { draft = first } }
      .onChange(of: input.learnedTrigger) { _, token in if !token.isEmpty { draft.trigger = token; draft.deviceKey = input.deviceKey } }
      .onDisappear { recording = false; input.learning = false }
      .confirmationDialog("删除这个宏？", isPresented: Binding(get: { deleteID != nil }, set: { if !$0 { deleteID = nil } })) {
        Button("删除宏", role: .destructive) { if let id = deleteID { input.delete(id); if draft.id == id { draft = MouseMacro() }; deleteID = nil } }
      }
  }
}

struct KeyboardCapture: NSViewRepresentable {
  @Binding var steps: [MacroStep]
  @Binding var recording: Bool
  func makeNSView(context: Context) -> CaptureArea {
    let view = CaptureArea()
    view.add = { steps.append($0) }
    view.finish = { recording = false }
    return view
  }
  func updateNSView(_ view: CaptureArea, context: Context) {
    view.add = { steps.append($0) }; view.finish = { recording = false }
  }
  static func dismantleNSView(_ view: CaptureArea, coordinator: ()) { view.releaseKeys(); view.timeout?.invalidate() }
  final class CaptureArea: NSView {
    var add: ((MacroStep) -> Void)?
    var finish: (() -> Void)?
    var timeout: Timer?
    private var previous: TimeInterval?
    private var held: [UInt16: String] = [:]
    private var count = 0
    override var acceptsFirstResponder: Bool { true }
    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      window?.makeFirstResponder(self)
      timeout = Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { [weak self] _ in self?.end() }
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool { if event.type == .keyDown { keyDown(with: event); return true }; return false }
    override func keyDown(with event: NSEvent) {
      if event.keyCode == 53 { end(); return }
      guard !event.isARepeat, held[event.keyCode] == nil else { return }
      append(event, down: true)
    }
    override func keyUp(with event: NSEvent) { if held[event.keyCode] != nil { append(event, down: false) } }
    override func resignFirstResponder() -> Bool { releaseKeys(); finish?(); return true }
    private func append(_ event: NSEvent, down: Bool) {
      if count >= 240 { end(); return }
      let delay = previous.map { Int(max(0, min(60_000, (event.timestamp - $0) * 1000))) } ?? 0
      previous = event.timestamp
      let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
      let symbols = (flags.contains(.control) ? "⌃" : "") + (flags.contains(.option) ? "⌥" : "") + (flags.contains(.shift) ? "⇧" : "") + (flags.contains(.command) ? "⌘" : "")
      let key = event.charactersIgnoringModifiers?.uppercased() ?? "键 \(event.keyCode)"
      let label = down ? symbols + (key == " " ? "空格" : key) : held[event.keyCode] ?? key
      if down { held[event.keyCode] = label } else { held.removeValue(forKey: event.keyCode) }
      count += 1
      add?(MacroStep(keyCode: event.keyCode, down: down, flags: UInt64(flags.rawValue), delayMS: delay, label: label))
    }
    func releaseKeys() {
      for (key, label) in held { add?(MacroStep(keyCode: key, down: false, flags: 0, delayMS: 0, label: label)) }
      held = [:]
    }
    private func end() { releaseKeys(); timeout?.invalidate(); finish?() }
  }
}

struct TiltView: View {
  @ObservedObject var input: InputActions
  var body: some View {
    Surface {
      HStack { ControlHeading(title: "滚轮倾斜", icon: "wheel"); Spacer(); Toggle("启用", isOn: $input.tilt.enabled).labelsHidden().toggleStyle(.switch).controlSize(.small).disabled(!input.monitoring) }
      if !input.monitoring { Button("启用当前鼠标监听") { input.startMonitoring() }.controlSize(.small) }
      Picker("倾斜动作", selection: $input.tilt.horizontal) { Text("水平滚动").tag(true); Text("前进 / 后退").tag(false) }.pickerStyle(.segmented)
      if input.tilt.horizontal {
        Toggle("按住持续滚动", isOn: $input.tilt.repeats).toggleStyle(.switch).controlSize(.small)
        Toggle("反转方向", isOn: $input.tilt.reverse).toggleStyle(.switch).controlSize(.small)
        if input.tilt.repeats {
          VStack(alignment: .leading, spacing: 8) {
            Text("首次等待  \(input.tilt.delayMS) ms").font(.system(size: 11)).monospacedDigit()
            Slider(value: Binding(get: { Double(input.tilt.delayMS) }, set: { input.tilt.delayMS = Int($0.rounded()) }), in: 100...2000)
            Text("重复间隔  \(input.tilt.intervalMS) ms").font(.system(size: 11)).monospacedDigit()
            Slider(value: Binding(get: { Double(input.tilt.intervalMS) }, set: { input.tilt.intervalMS = Int($0.rounded()) }), in: 20...1000)
          }
        }
      }
      Text("本机附加动作，需要辅助功能权限；不拦截系统原生输入。松开、断连和休眠停止重复。").font(.system(size: 10)).foregroundStyle(.secondary)
      if !input.accessReady { Button("允许辅助功能") { input.requestAccess() }.controlSize(.small) }
    }.onChange(of: input.tilt) { _, _ in input.saveTilt() }
  }
}
