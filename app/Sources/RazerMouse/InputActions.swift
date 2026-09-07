// SPDX-License-Identifier: GPL-2.0-or-later
import AppKit
import IOKit.hid
import RazerBindings
import SwiftUI

struct MacroStep: Codable, Equatable, Identifiable {
  var id = UUID()
  var keyCode: UInt16
  var down: Bool
  var flags: UInt64
  var delayMS: Int
  var label: String
}
struct MouseMacro: Codable, Identifiable, Equatable {
  var id = UUID()
  var name = "新建宏"
  var deviceKey = ""
  var trigger = ""
  var enabled = false
  var steps: [MacroStep] = []
}
struct TiltPreferences: Codable, Equatable {
  var enabled = false
  var horizontal = true
  var repeats = true
  var delayMS = 250
  var intervalMS = 80
  var reverse = false
  var valid: Bool { (100...2000).contains(delayMS) && (20...1000).contains(intervalMS) }
}
enum MacroValidation {
  static func error(_ steps: [MacroStep]) -> String? {
    guard !steps.isEmpty else { return "请先录制按键" }
    guard steps.count <= 256 else { return "最多保留 256 个动作" }
    guard steps.allSatisfy({ (0...60_000).contains($0.delayMS) && $0.keyCode < 128 }) else { return "按键或间隔超出范围" }
    guard steps.reduce(0, { $0 + $1.delayMS }) <= 60_000 else { return "宏的总时长不能超过 60 秒" }
    var held: Set<UInt16> = []
    for step in steps {
      if step.down {
        guard !held.contains(step.keyCode) else { return "存在重复按下且未释放的按键" }
        held.insert(step.keyCode)
      } else {
        guard held.remove(step.keyCode) != nil else { return "存在没有对应按下动作的松开事件" }
      }
    }
    return held.isEmpty ? nil : "存在未释放的按键，请重新录制完整按下和松开过程"
  }
}

/// Linux's report constants are generated from the pinned reference, not model-specific UI assumptions.
enum MouseInputReport {
  static let map: [String: Int] = {
    guard let url = Bundle.module.url(forResource: "input-report-map", withExtension: "json"),
      let data = try? Data(contentsOf: url), let map = try? JSONDecoder().decode([String: Int].self, from: data)
    else { return [:] }
    return map
  }()
  static func tiltMask(_ bytes: [UInt8]) -> Set<Int> {
    guard let first = bytes.first, let left = map["BIT_TILT_L"], let right = map["BIT_TILT_R"] else { return [] }
    var directions: Set<Int> = []
    if first & (1 << left) != 0 { directions.insert(-1) }
    if first & (1 << right) != 0 { directions.insert(1) }
    return directions
  }
  static func report4(_ bytes: [UInt8]) -> Set<Int> {
    guard bytes.count == 16, bytes.first == 4 else { return [] }
    return Set(bytes.dropFirst().filter { $0 != 0 }.map(Int.init))
  }
  static func label(_ token: String) -> String {
    if token.hasPrefix("button:") { return "鼠标按键 " + token.dropFirst(7) }
    if token == "tilt:-1" { return "滚轮向左倾斜" }
    if token == "tilt:1" { return "滚轮向右倾斜" }
    let code = Int(token.replacingOccurrences(of: "report4:", with: ""))
    let names = ["REP4_DPI_UP": "DPI 增加", "REP4_DPI_DN": "DPI 减少", "REP4_SNIPER": "狙击键", "REP4_PROFILE": "配置键", "REP4_DPI_CYCLE": "DPI 切换", "REP4_SCROLL": "滚轮模式键"]
    return names.first { map[$0.key] == code }?.value ?? "扩展按键 \(code.map(String.init) ?? token)"
  }
}

@MainActor final class InputActions: ObservableObject {
  @Published var macros: [MouseMacro] = []
  @Published var tilt = TiltPreferences()
  @Published var status = "软件动作默认关闭"
  @Published var deviceKey = ""
  @Published var learning = false
  @Published var learnedTrigger = ""
  @Published var playing: UUID?
  @Published var accessReady = false
  @Published var monitoring = false
  @Published var macrosEnabled = false
  var tiltSupported = false
  private var info: DeviceInfo?
  private var manager: IOHIDManager?
  private var master: IOHIDDevice?
  private var reportState: [UInt64: Set<Int>] = [:]
  private var tiltState: Set<Int> = []
  private var downTokens: Set<String> = []
  private var playback: Task<Void, Never>?
  private var repeatTask: Task<Void, Never>?
  private var heldKeys: Set<UInt16> = []
  private var destination: pid_t?
  private var learnTimeout: Task<Void, Never>?
  private var observers: [NSObjectProtocol] = []
  private let defaults: UserDefaults
  private let live: Bool
  private let vendorID: UInt16
  init(vendorID: UInt16, live: Bool = true, defaults: UserDefaults = .standard) {
    self.vendorID = vendorID; self.live = live; self.defaults = defaults
    if let data = defaults.data(forKey: "mouseMacros.v1"), let values = try? JSONDecoder().decode([MouseMacro].self, from: data) { macros = values }
    guard live else { return }
    accessReady = CGPreflightPostEventAccess()
    let center = NSWorkspace.shared.notificationCenter
    observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
      Task { @MainActor in self?.stopMonitoring() }
    })
    observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
      let pid = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
      Task { @MainActor in if let self, let target = self.destination, target != pid { self.stopPlayback() } }
    })
  }
  func configure(_ info: DeviceInfo?) {
    guard self.info?.id != info?.id else { return }
    stopMonitoring()
    self.info = info; tiltSupported = info?.tiltSupported == true
    deviceKey = ""; macrosEnabled = false; tilt = TiltPreferences()
  }
  func refreshAccess() {
    guard live else { return }
    accessReady = CGPreflightPostEventAccess()
    if !accessReady { stopPlayback(); repeatTask?.cancel(); macrosEnabled = false }
  }
  func requestAccess() {
    accessReady = CGPreflightPostEventAccess()
    if !accessReady { _ = CGRequestPostEventAccess() }
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
  }
  func startMonitoring() {
    guard live, manager == nil, let info else { return }
    accessReady = CGPreflightPostEventAccess()
    let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: vendorID, kIOHIDProductIDKey: info.pid] as CFDictionary)
    IOHIDManagerSetInputValueMatching(manager, [kIOHIDElementUsagePageKey: kHIDPage_Button] as CFDictionary)
    IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
    let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    guard result == kIOReturnSuccess else {
      IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
      status = "无法监听鼠标，请检查输入监控权限"; return
    }
    let devices = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
    let exact = devices.first { device in info.id == "DevSrvsID:\(Self.registryID(device))" }
    let physical = Dictionary(grouping: devices, by: Self.physicalKey)
    guard let master = exact ?? (physical.count == 1 ? devices.first : nil) else {
      IOHIDManagerClose(manager, 0)
      IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
      status = "无法唯一匹配输入设备，请重新连接目标鼠标"; return
    }
    self.master = master; self.manager = manager
    deviceKey = Self.physicalKey(master)
    if let data = defaults.data(forKey: "tilt." + deviceKey), let saved = try? JSONDecoder().decode(TiltPreferences.self, from: data), saved.valid { tilt = saved }
    // Listening and activation are explicit each launch / reconnect. Never replay actions on reconnect.
    tilt.enabled = false
    let context = Unmanaged.passUnretained(self).toOpaque()
    IOHIDManagerRegisterInputValueCallback(manager, { context, _, _, value in
      guard let context else { return }
      let element = IOHIDValueGetElement(value)
      guard IOHIDElementGetUsagePage(element) == 9, IOHIDElementGetUsage(element) >= 3 else { return }
      let device = IOHIDElementGetDevice(element)
      let usage = IOHIDElementGetUsage(element), pressed = IOHIDValueGetIntegerValue(value) != 0
      MainActor.assumeIsolated { Unmanaged<InputActions>.fromOpaque(context).takeUnretainedValue().input(device, token: "button:\(usage)", down: pressed) }
    }, context)
    IOHIDManagerRegisterInputReportCallback(manager, { context, _, sender, _, reportID, bytes, length in
      guard let context, let sender, length > 0, length <= 512 else { return }
      MainActor.assumeIsolated {
        let owner = Unmanaged<InputActions>.fromOpaque(context).takeUnretainedValue()
        guard owner.tiltSupported || (length == 16 && bytes[0] == 4) else { return }
        let device = Unmanaged<IOHIDDevice>.fromOpaque(sender).takeUnretainedValue()
        owner.report(device, reportID: reportID, bytes: Array(UnsafeBufferPointer(start: bytes, count: length)))
      }
    }, context)
    IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, _ in
      guard let context else { return }
      MainActor.assumeIsolated {
        let selfRef = Unmanaged<InputActions>.fromOpaque(context).takeUnretainedValue()
        selfRef.stopPlayback(); selfRef.repeatTask?.cancel(); selfRef.downTokens = []; selfRef.status = "输入接口已断开，请重新启用监听"
        selfRef.macrosEnabled = false; selfRef.tilt.enabled = false
      }
    }, context)
    monitoring = true; status = "正在监听当前鼠标的按键；原生按键行为保留"
  }
  func stopMonitoring() {
    stopPlayback(); repeatTask?.cancel(); repeatTask = nil
    learnTimeout?.cancel(); learning = false
    if let manager {
      IOHIDManagerRegisterInputValueCallback(manager, nil, nil)
      IOHIDManagerRegisterInputReportCallback(manager, nil, nil)
      IOHIDManagerRegisterDeviceRemovalCallback(manager, nil, nil)
      IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
      IOHIDManagerClose(manager, 0)
    }
    manager = nil; master = nil; monitoring = false; macrosEnabled = false
    reportState = [:]; tiltState = []; downTokens = []
  }
  static func registryID(_ device: IOHIDDevice) -> UInt64 {
    var result: UInt64 = 0
    IORegistryEntryGetRegistryEntryID(IOHIDDeviceGetService(device), &result)
    return result
  }
  static func physicalKey(_ device: IOHIDDevice) -> String {
    let pid = (IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? NSNumber)?.stringValue ?? "?"
    let serial = IOHIDDeviceGetProperty(device, kIOHIDSerialNumberKey as CFString) as? String ?? ""
    let location = (IOHIDDeviceGetProperty(device, kIOHIDLocationIDKey as CFString) as? NSNumber)?.stringValue
    return "\(pid):" + (!serial.isEmpty ? serial : location ?? "registry-\(registryID(device))")
  }
  private func matches(_ device: IOHIDDevice) -> Bool { Self.physicalKey(device) == deviceKey }
  private func input(_ device: IOHIDDevice, token: String, down: Bool) {
    guard matches(device) else { return }
    guard down != downTokens.contains(token) else { return }
    if down { downTokens.insert(token) } else { downTokens.remove(token) }
    if learning && down { learnedTrigger = token; learning = false; learnTimeout?.cancel(); status = "已识别：" + MouseInputReport.label(token); return }
    guard down, macrosEnabled, !learning, playing == nil, let macro = macros.first(where: { $0.enabled && $0.deviceKey == deviceKey && $0.trigger == token }) else { return }
    play(macro)
  }
  private func report(_ device: IOHIDDevice, reportID: UInt32, bytes: [UInt8]) {
    guard matches(device) else { return }
    let usage = (IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString) as? NSNumber)?.intValue
    if usage == Int(kHIDUsage_GD_Keyboard), bytes.count == 16, bytes.first == 4 {
      let id = Self.registryID(device), current = MouseInputReport.report4(bytes), previous = reportState[id] ?? []
      for code in current.subtracting(previous) { input(device, token: "report4:\(code)", down: true) }
      for code in previous.subtracting(current) { input(device, token: "report4:\(code)", down: false) }
      reportState[id] = current
    }
    guard tiltSupported, reportID == 0, usage == Int(kHIDUsage_GD_Mouse), !bytes.isEmpty else { return }
    let current = MouseInputReport.tiltMask(bytes), previous = tiltState
    tiltState = current
    for direction in previous.subtracting(current) { input(device, token: "tilt:\(direction)", down: false) }
    for direction in current.subtracting(previous) {
      let wasLearning = learning
      input(device, token: "tilt:\(direction)", down: true)
      if tilt.enabled && !wasLearning && current.count == 1 { startTilt(direction) }
    }
    if current.count != 1 { repeatTask?.cancel(); repeatTask = nil }
  }
  func learn() {
    if !monitoring { startMonitoring() }
    guard monitoring else { return }
    stopPlayback(); repeatTask?.cancel(); learnedTrigger = ""; learning = true; status = "请按一下要绑定的鼠标按键（15 秒内）"
    learnTimeout?.cancel()
    learnTimeout = Task { [weak self] in
      try? await Task.sleep(for: .seconds(15))
      guard !Task.isCancelled, let self, self.learning else { return }
      self.learning = false; self.status = "尚未捕获按键，可重新识别"
    }
  }
  func save(_ macro: MouseMacro) -> Bool {
    if let error = MacroValidation.error(macro.steps) { status = error; return false }
    guard !macro.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { status = "请填写名称"; return false }
    if macro.enabled && (macro.trigger.isEmpty || macro.deviceKey.isEmpty) { status = "启用前请识别目标鼠标按键"; return false }
    if macro.enabled && macros.contains(where: { $0.id != macro.id && $0.enabled && $0.deviceKey == macro.deviceKey && $0.trigger == macro.trigger }) { status = "这个按键已经绑定另一个宏"; return false }
    if let index = macros.firstIndex(where: { $0.id == macro.id }) { macros[index] = macro } else { macros.append(macro) }
    persist(); status = "宏已保存到本机"; return true
  }
  func delete(_ id: UUID) { stopPlayback(); macros.removeAll { $0.id == id }; persist() }
  private func persist() { if let data = try? JSONEncoder().encode(macros) { defaults.set(data, forKey: "mouseMacros.v1") } }
  func saveTilt() {
    repeatTask?.cancel()
    guard tilt.valid else { status = "滚动间隔超出范围"; return }
    if tilt.enabled && !CGPreflightPostEventAccess() { tilt.enabled = false; status = "请先允许辅助功能，再启用倾斜动作" }
    if let data = try? JSONEncoder().encode(tilt), !deviceKey.isEmpty { defaults.set(data, forKey: "tilt." + deviceKey) }
  }
  private func startTilt(_ rawDirection: Int) {
    repeatTask?.cancel()
    guard tilt.valid, CGPreflightPostEventAccess() else { status = "请允许辅助功能以发送滚动事件"; return }
    let direction = rawDirection * (tilt.reverse ? -1 : 1)
    let preferences = tilt
    sendTilt(direction, horizontal: preferences.horizontal)
    guard preferences.repeats && preferences.horizontal else { return }
    repeatTask = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(preferences.delayMS))
      while !Task.isCancelled {
        guard let self, self.tilt.enabled, self.monitoring, self.tiltState.contains(rawDirection) else { return }
        self.sendTilt(direction, horizontal: true)
        try? await Task.sleep(for: .milliseconds(preferences.intervalMS))
      }
    }
  }
  private func sendTilt(_ direction: Int, horizontal: Bool) {
    if horizontal {
      CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: 0, wheel2: Int32(direction), wheel3: 0)?.post(tap: .cgSessionEventTap)
    } else {
      let point = CGEvent(source: nil)?.location ?? .zero
      let button = CGMouseButton(rawValue: direction < 0 ? 3 : 4)!
      CGEvent(mouseEventSource: nil, mouseType: .otherMouseDown, mouseCursorPosition: point, mouseButton: button)?.post(tap: .cgSessionEventTap)
      CGEvent(mouseEventSource: nil, mouseType: .otherMouseUp, mouseCursorPosition: point, mouseButton: button)?.post(tap: .cgSessionEventTap)
    }
  }
  func test(_ macro: MouseMacro) {
    guard MacroValidation.error(macro.steps) == nil else { status = MacroValidation.error(macro.steps) ?? ""; return }
    stopPlayback(); status = "3 秒后开始，请切换到测试窗口"
    playback = Task { [weak self] in
      try? await Task.sleep(for: .seconds(3))
      guard !Task.isCancelled else { return }
      self?.play(macro)
    }
  }
  func play(_ macro: MouseMacro) {
    guard live, MacroValidation.error(macro.steps) == nil, CGPreflightPostEventAccess() else { status = "请检查宏内容，并允许辅助功能"; return }
    guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { status = "请先切换到接收宏的窗口"; return }
    stopPlayback(); destination = app.processIdentifier; playing = macro.id; status = "正在执行：" + macro.name
    // Bind this execution to one recipient; focus changes must not redirect keystrokes.
    let target = app.processIdentifier
    playback = Task { [weak self] in
      for step in macro.steps {
        try? await Task.sleep(for: .milliseconds(step.delayMS))
        guard !Task.isCancelled, let self, self.destination == target else { return }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target else { self.stopPlayback(); return }
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: step.keyCode, keyDown: step.down) else { self.stopPlayback(); return }
        event.flags = CGEventFlags(rawValue: step.flags)
        event.postToPid(target)
        if step.down { self.heldKeys.insert(step.keyCode) } else { self.heldKeys.remove(step.keyCode) }
      }
      self?.stopPlayback(); self?.status = "宏执行完成"
    }
  }
  func stopPlayback() {
    playback?.cancel(); playback = nil
    // Cancellation must release keys in the original process, even after focus moved.
    if let destination {
      for key in heldKeys { CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: false)?.postToPid(destination) }
    }
    heldKeys = []; destination = nil; playing = nil
  }
}
