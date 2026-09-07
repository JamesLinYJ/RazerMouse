// SPDX-License-Identifier: GPL-2.0-or-later
import AppKit
import Combine
import SwiftUI

/// AppKit owns the complete popover rectangle, including its opaque backing.
/// SwiftUI owns only the controls; no MenuBarExtra safe-area or glass host is involved.
@MainActor final class StatusPopover: NSObject, NSPopoverDelegate {
  private let model: MouseModel
  private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  private let popover = NSPopover()
  private var observations: Set<AnyCancellable> = []
  init(model: MouseModel) {
    self.model = model
    super.init()
    popover.behavior = .transient
    popover.animates = false
    popover.delegate = self
    let controller = NSViewController()
    let backing = OpaquePopoverView(frame: NSRect(x: 0, y: 0, width: 360, height: 650))
    let hosting = NSHostingView(rootView: PopoverContent(model: model) { [weak self] height in
      DispatchQueue.main.async { self?.resize(to: height) }
    })
    hosting.translatesAutoresizingMaskIntoConstraints = false
    backing.addSubview(hosting)
    NSLayoutConstraint.activate([
      hosting.leadingAnchor.constraint(equalTo: backing.leadingAnchor),
      hosting.trailingAnchor.constraint(equalTo: backing.trailingAnchor),
      hosting.topAnchor.constraint(equalTo: backing.topAnchor),
      hosting.bottomAnchor.constraint(equalTo: backing.bottomAnchor),
    ])
    controller.view = backing
    popover.contentViewController = controller
    popover.contentSize = NSSize(width: 360, height: hosting.fittingSize.height)
    if let button = item.button {
      button.target = self; button.action = #selector(toggle)
      button.imagePosition = .imageLeft
      button.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
      button.setAccessibilityLabel("Razer Mouse 控制面板")
    }
    model.objectWillChange.sink { [weak self] _ in
      DispatchQueue.main.async { self?.updateStatusItem() }
    }.store(in: &observations)
    model.$panelPresented.removeDuplicates().receive(on: RunLoop.main).sink { [weak self] visible in
      guard let self else { return }
      if visible { self.show() } else { self.popover.performClose(nil) }
    }.store(in: &observations)
    updateStatusItem()
  }
  private func updateStatusItem() {
    guard let button = item.button else { return }
    let name = model.connected ? "glyph-mouse" : "glyph-disconnected"
    let image = Bundle.module.image(forResource: NSImage.Name(name))?.copy() as? NSImage
    image?.isTemplate = true; image?.size = NSSize(width: 17, height: 19)
    button.image = image
    button.title = " " + (model.connected && model.responding ? model.batteryText : "—")
    button.toolTip = model.title + " · " + model.statusLabel
  }
  @objc private func toggle() { model.panelPresented = !popover.isShown }
  private func show() {
    guard !popover.isShown, let button = item.button else { return }
    popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    popover.contentViewController?.view.window?.makeKey()
    model.refresh()
  }
  // Use measured content height so expanded controls and feedback do not leave host gaps.
  private func resize(to height: CGFloat) {
    guard height.isFinite, height > 0 else { return }
    let size = NSSize(width: 360, height: ceil(height))
    guard abs(popover.contentSize.height - size.height) > 0.5 else { return }
    popover.contentSize = size
  }
  func popoverDidClose(_ notification: Notification) { model.panelPresented = false }
  func close() { popover.performClose(nil); NSStatusBar.system.removeStatusItem(item) }
}

private struct PopoverHeightKey: PreferenceKey {
  static var defaultValue: CGFloat = 0
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
private struct PopoverContent: View {
  @ObservedObject var model: MouseModel
  var heightChanged: (CGFloat) -> Void
  var body: some View {
    Panel(model: model)
      .fixedSize(horizontal: false, vertical: true)
      .background(GeometryReader { proxy in Color.clear.preference(key: PopoverHeightKey.self, value: proxy.size.height) })
      .onPreferenceChange(PopoverHeightKey.self, perform: heightChanged)
  }
}
final class OpaquePopoverView: NSView {
  override var isOpaque: Bool { true }
  override func draw(_ dirtyRect: NSRect) {
    NSColor.windowBackgroundColor.setFill()
    dirtyRect.fill()
  }
  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    needsDisplay = true
  }
}
