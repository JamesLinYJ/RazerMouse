// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import RazerBindings
import XCTest

final class HardwareTests: XCTestCase {
  func testRepeatedReadFromShortLivedCallerThreads() throws {
    guard ProcessInfo.processInfo.environment["RAZER_HARDWARE_READ"] == "1" else {
      throw XCTSkip("Explicit hardware test only")
    }
    final class Outcome: @unchecked Sendable {
      private let lock = NSLock()
      private var failure: String?
      func record(_ message: String) {
        lock.lock()
        failure = message
        lock.unlock()
      }
      func read() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return failure
      }
    }
    let outcome = Outcome()
    for _ in 0..<24 {
      let done = DispatchSemaphore(value: 0)
      Thread.detachNewThread {
        defer { done.signal() }
        do {
          let controller = Controller()
          let devices = try controller.devices()
          guard let device = devices.first else {
            outcome.record("No test device")
            return
          }
          let snapshot = try controller.snapshot(id: device.id)
          if !snapshot.errors.isEmpty { outcome.record(snapshot.errors.joined(separator: "; ")) }
        } catch { outcome.record(String(describing: error)) }
      }
      XCTAssertEqual(done.wait(timeout: .now() + 10), .success)
    }
    XCTAssertNil(outcome.read())
  }
  func testSnapshotThroughABI() throws {
    guard ProcessInfo.processInfo.environment["RAZER_HARDWARE_READ"] == "1" else {
      throw XCTSkip("Hardware readback requires a connected test device")
    }
    let controller = Controller()
    let devices = try controller.devices()
    XCTAssertFalse(devices.isEmpty)
    var report: [[String: Any]] = []
    for device in devices {
      let snapshot = try controller.snapshot(id: device.id)
      report.append([
        "name": device.name, "pid": device.pid, "connection": device.connection,
        "battery": snapshot.battery as Any? ?? NSNull(),
        "charging": snapshot.charging as Any? ?? NSNull(),
        "dpi": snapshot.dpi.map { [$0.x, $0.y] } as Any? ?? NSNull(),
        "poll_rate": snapshot.pollRate as Any? ?? NSNull(),
        "stages": snapshot.stages.map { [$0.x, $0.y] },
        "active_stage": snapshot.activeStage as Any? ?? NSNull(),
        "idle_seconds": snapshot.idleSeconds as Any? ?? NSNull(),
        "low_battery_raw": snapshot.lowBattery as Any? ?? NSNull(),
        "firmware": snapshot.firmware as Any? ?? NSNull(),
        "errors": snapshot.errors,
        "source": "Swift XCTest -> UniFFI ABI -> Rust -> HID",
        "time": ISO8601DateFormatter().string(from: Date()),
      ])
      XCTAssertTrue(snapshot.errors.isEmpty, snapshot.errors.joined(separator: "; "))
    }
    let path = try XCTUnwrap(ProcessInfo.processInfo.environment["RAZER_HARDWARE_REPORT"])
    try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
      .write(to: URL(fileURLWithPath: path))
  }
}
