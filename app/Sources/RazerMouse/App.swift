// SPDX-License-Identifier: GPL-2.0-or-later
import AppKit
import SwiftUI

@main struct RazerMouseApp: App {
  @NSApplicationDelegateAdaptor(MouseAppDelegate.self) private var delegate
  var body: some Scene { Settings { EmptyView() } }
}

@MainActor final class MouseAppDelegate: NSObject, NSApplicationDelegate {
  private var model: MouseModel?
  private var statusPopover: StatusPopover?
  func applicationDidFinishLaunching(_ notification: Notification) {
    let model = MouseModel()
    self.model = model
    statusPopover = StatusPopover(model: model)
    model.openSettings()
  }
  func applicationWillTerminate(_ notification: Notification) {
    model?.inputs.stopMonitoring()
    statusPopover?.close()
  }
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    model?.openSettings()
    return true
  }
}
