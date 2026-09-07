// SPDX-License-Identifier: GPL-2.0-or-later
import AppKit
import RazerBindings
import SwiftUI

private enum RefreshSchedule {
  // Product refresh policy, independent of any device model.
  static let enumeration: TimeInterval = 5
  static let battery: TimeInterval = 60
}

@MainActor final class MouseModel: ObservableObject {
  @Published var devices: [DeviceInfo] = []
  @Published var selected = ""
  @Published var state: Snapshot?
  @Published var panelPresented = false
  @Published var busy = false
  @Published var message = ""
  @Published var failed = false
  @Published var connected = false
  @Published var synapseRunning = false
  @Published var accessDenied = false
  @Published var connectionNotice = ""
  @Published var responding = true
  @Published private(set) var lastUpdated: Date?
  @Published private(set) var operationRevision: UInt64 = 0
  @Published var dpiText = ""
  @Published var advancedValues: [String: String] = [:]
  let core = Controller()
  let inputs: InputActions
  private let worker = DispatchQueue(label: "mouse.protocol", qos: .utility)
  private var timer: Timer?
  private var settingsWindow: NSWindow?
  private var lastRefresh = Date.distantPast
  private var sleeping = false
  private var scanning = false
  private var pendingScan = false
  private var deviceNotifications: DeviceNotifications?
  private var connectionTask: Task<Void, Never>?
  private var advancedRequested: Set<String> = []
  private var observers: [NSObjectProtocol] = []
  private let monitoring: Bool
  init(monitoring: Bool = true) {
    self.monitoring = monitoring
    inputs = InputActions(vendorID: core.vendorId(), live: monitoring)
    guard monitoring else { return }
    selected = UserDefaults.standard.string(forKey: "selectedDevice") ?? ""
    do {
      deviceNotifications = try DeviceNotifications(vendorID: core.vendorId()) { [weak self] in
        Task { @MainActor in self?.deviceTopologyChanged() }
      }
    } catch {
      NSLog("Device notifications unavailable; periodic enumeration remains active: %@", error.localizedDescription)
    }
    timer = Timer.scheduledTimer(withTimeInterval: RefreshSchedule.enumeration, repeats: true) {
      [weak self] _ in
      Task { @MainActor in self?.tick() }
    }
    let center = NSWorkspace.shared.notificationCenter
    observers.append(
      center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) {
        [weak self] _ in Task { @MainActor in self?.sleeping = true }
      })
    observers.append(
      center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) {
        [weak self] _ in
        Task { @MainActor in
          self?.sleeping = false
          self?.scan(refresh: true)
        }
      })
    scan()
  }
  var info: DeviceInfo? { devices.first { $0.id == selected } ?? state?.device }
  var title: String {
    info?.name ?? "Razer Mouse"
  }
  func has(_ name: String) -> Bool { info?.attributes.contains(name) == true }
  var batteryText: String { state?.battery.map { "\($0)%" } ?? "—" }
  var statusLabel: String {
    !connected ? "已断开 · 上次读数" : !responding ? "设备暂未响应" : state?.charging == true ? "正在充电" : "已连接"
  }
  var batteryColor: Color {
    guard connected, let battery = state?.battery else { return .secondary }
    guard let threshold = state?.lowBattery else { return MouseStyle.accent }
    return Double(battery) <= Double(threshold) * 100 / 255 ? .orange : MouseStyle.accent
  }
  func range(_ name: String) -> ControlRange? { info?.ranges.first { $0.name == name } }
  func advancedNumber(_ name: String) -> UInt32? { advancedValues[name].flatMap(UInt32.init) }
  private func accept(_ snapshot: Snapshot) {
    let hasReading = snapshot.battery != nil || snapshot.dpi != nil || snapshot.pollRate != nil
      || snapshot.firmware != nil
    if !snapshot.errors.isEmpty && !hasReading {
      responding = false
      failed = true
      message = "设备暂未响应，保留上次读数。请检查鼠标电源或连接。"
      return
    }
    responding = true
    state = snapshot
    lastRefresh = Date()
    lastUpdated = lastRefresh
    dpiText = snapshot.dpi.map { "\($0.x)" } ?? ""
    failed = !snapshot.errors.isEmpty
    message = snapshot.errors.first ?? ""
  }
  func openAccessSettings() {
    guard
      let url = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    else { return }
    NSWorkspace.shared.open(url)
  }
  func openSettings() {
    if settingsWindow == nil {
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 900, height: 680),
        styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
      window.title = "Razer Mouse"
      window.titlebarAppearsTransparent = true
      window.backgroundColor = .windowBackgroundColor
      window.contentView = NSHostingView(rootView: SettingsView(model: self))
      window.isReleasedWhenClosed = false
      window.center()
      settingsWindow = window
    }
    settingsWindow?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
  func tick() {
    guard !sleeping else { return }
    inputs.refreshAccess()
    scan(refresh: !responding || Date().timeIntervalSince(lastRefresh) >= RefreshSchedule.battery)
  }
  func deviceTopologyChanged() {
    NSLog("Razer device topology changed; requesting immediate refresh")
    pendingScan = true
    connectionNotice = "检测到连接变化，正在同步…"
    connectionTask?.cancel()
    connectionTask = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(150))
      guard !Task.isCancelled else { return }
      self?.scan(refresh: true)
    }
  }
  // A hotplug notification can arrive during a write; consume it when I/O is idle.
  private func drainPendingScan() {
    if pendingScan && !busy && !scanning { scan(refresh: true) }
  }
  // Kept separate from I/O so unplug/replug transitions can be regression tested.
  func reconcileDevices(_ list: [DeviceInfo]) -> Bool {
    let previous = selected
    let wasConnected = connected
    accessDenied = false
    devices = list
    if !list.contains(where: { $0.id == selected }) {
      selected = list.first?.id ?? ""
      if !list.isEmpty {
        state = nil
        dpiText = ""
        advancedValues = [:]
        advancedRequested = []
      }
    }
    connected = !list.isEmpty
    inputs.configure(list.first { $0.id == selected })
    if wasConnected && !connected {
      connectionNotice = "鼠标已断开 · 设置已停用"
      message = ""
      failed = false
    } else if connected && (!wasConnected || previous != selected) {
      responding = true
      connectionNotice = "鼠标已连接 · 正在读取设置"
    } else if connected { connectionNotice = "" }
    return connected && (!wasConnected || previous != selected || state?.device.id != selected)
  }
  func scan(refresh: Bool = false) {
    guard monitoring, !sleeping else { return }
    guard !scanning, !busy else { if refresh { pendingScan = true }; return }
    pendingScan = false
    scanning = true
    synapseRunning = NSWorkspace.shared.runningApplications.contains {
      $0.bundleIdentifier == "com.razer.appengine.app"
    }
    let selectedID = selected
    worker.async { [weak self] in
      guard let self else { return }
      let result = Result { () -> ([DeviceInfo], Bool?) in
        let list = try self.core.devices()
        let selected = list.first { $0.id == selectedID } ?? list.first
        // A receiver can stay enumerated while its mouse is switched off or asleep.
        // A failed query means "not responding", never a fabricated power-off status.
        var response: Bool?
        if let selected, selected.connection == "无线接收器",
          selected.readableAttributes.contains("charge_level") {
          response = (try? self.core.readControl(id: selected.id, name: "charge_level")) != nil
        }
        return (list, response)
      }
      Task { @MainActor in
        self.scanning = false
        defer { self.drainPendingScan() }
        switch result {
        case .success(let (list, response)):
          let changed = self.reconcileDevices(list)
          if let response {
            self.responding = response
            if !response { self.connectionNotice = "接收器已连接 · 鼠标暂未响应"; self.inputs.stopMonitoring() }
          }
          if self.connected && (refresh || changed) {
            self.refresh()
          }
        case .failure(let error):
          self.connected = false
          self.showError(error)
        }
      }
    }
  }
  func select(_ id: String) {
    selected = id
    inputs.configure(devices.first { $0.id == id })
    state = nil
    dpiText = ""
    advancedValues = [:]
    advancedRequested = []
    UserDefaults.standard.set(id, forKey: "selectedDevice")
    refresh()
  }
  func refresh() {
    guard monitoring, connected, !busy else { return }
    busy = true
    let id = selected
    worker.async { [weak self] in
      guard let self else { return }
      let result = Result { try self.core.snapshot(id: id) }
      Task { @MainActor in
        self.busy = false
        defer { self.drainPendingScan() }
        guard self.selected == id else { return }
        switch result {
        case .success(let snapshot):
          self.accept(snapshot)
          self.readAdvanced(Array(self.advancedRequested))
        case .failure(let e): self.showError(e)
        }
      }
    }
  }
  func perform(_ action: @escaping (Controller, String) throws -> Void, success: String = "已回读确认") {
    guard connected, !busy else { return }
    busy = true
    failed = false
    message = "正在应用…"
    let id = selected
    worker.async { [weak self] in
      guard let self else { return }
      let result = Result {
        try action(self.core, id)
        return try self.core.snapshot(id: id)
      }
      Task { @MainActor in
        self.busy = false
        defer { self.drainPendingScan() }
        guard id == self.selected else { return }
        switch result {
        case .success(let snapshot):
          self.accept(snapshot)
          if !self.failed { self.message = success }
          self.operationRevision &+= 1
          self.readAdvanced(Array(self.advancedRequested))
          Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if self.message == success { self.message = "" }
          }
        case .failure(let e):
          self.dpiText = self.state?.dpi.map { "\($0.x)" } ?? ""
          self.showError(e)
          self.readAdvanced(Array(self.advancedRequested))
        }
      }
    }
  }
  func setDpi() {
    guard let dpi = UInt32(dpiText) else {
      showErrorText("请输入有效的 DPI 数值")
      return
    }
    perform(
      { c, id in _ = try c.setDpi(id: id, x: dpi, y: dpi) },
      success: info?.cachedAttributes.contains("dpi") == true ? "已发送 · 设备不支持硬件回读" : "已回读确认")
  }
  func stage(_ index: Int) {
    guard let s = state else { return }
    perform { c, id in try c.setStages(id: id, stages: s.stages, active: UInt32(index + 1)) }
  }
  func number(_ name: String, _ value: UInt32) {
    let message = info?.cachedAttributes.contains(name) == true ? "已发送 · 设备不支持硬件回读" : "已回读确认"
    perform({ c, id in _ = try c.setNumber(id: id, name: name, value: value) }, success: message)
  }
  func applyLighting(_ writes: [LightingWrite], payload: Data, requested: Int) {
    guard connected, !busy, !writes.isEmpty else { return }
    busy = true; failed = false; message = "正在同步灯光…"
    let id = selected
    worker.async { [weak self] in
      guard let self else { return }
      var successes: Set<String> = []
      var failures: [String] = []
      for write in writes {
        do {
          try self.core.writeControl(id: write.deviceID, name: write.attribute, payload: payload)
          successes.insert(write.deviceID)
        } catch { failures.append("\(write.deviceName)：\(error.localizedDescription)") }
      }
      let sent = successes.count
      let attempted = Set(writes.map(\.deviceID)).count
      let errors = failures
      Task { @MainActor in
        self.busy = false
        defer { self.drainPendingScan() }
        guard id == self.selected else { return }
        self.operationRevision &+= 1
        self.failed = !errors.isEmpty
        self.message = errors.isEmpty
          ? "已发送到 \(sent) 台设备" + (requested > attempted ? " · \(requested - attempted) 台不支持此效果" : "")
          : "部分发送失败 · " + errors.joined(separator: "；")
        if errors.isEmpty {
          let message = self.message
          Task { try? await Task.sleep(for: .seconds(4)); if self.message == message { self.message = "" } }
        }
      }
    }
  }
  func readAdvanced(_ names: [String]) {
    guard monitoring, connected else { return }
    let id = selected
    let names = names.filter { info?.readableAttributes.contains($0) == true }
    advancedRequested.formUnion(names)
    worker.async { [weak self] in
      guard let self else { return }
      var values: [String: String] = [:]
      for name in names {
        if let v = try? self.core.readText(id: id, name: name) { values[name] = v }
      }
      Task { @MainActor in
        if id == self.selected {
          for name in names { self.advancedValues.removeValue(forKey: name) }
          self.advancedValues.merge(values) { _, new in new }
        }
      }
    }
  }
  func showError(_ error: Swift.Error) {
    let detail = error.localizedDescription
    accessDenied = detail.contains("not permitted") || detail.contains("0xE00002E2")
    showErrorText(
      accessDenied
        ? "macOS 尚未允许访问鼠标，请在输入监控中允许 Razer Mouse。"
        : detail.replacingOccurrences(of: "razer_core.", with: ""))
  }
  func showErrorText(_ text: String) {
    dpiText = state?.dpi.map { "\($0.x)" } ?? ""
    operationRevision &+= 1
    failed = true
    message = text
  }
}
