// SPDX-License-Identifier: GPL-2.0-or-later
import XCTest
import RazerBindings
@testable import RazerMouse

final class FeatureTests: XCTestCase {
  func testMacroRejectsUnreleasedKeysAndUnboundedDelays() {
    let down = MacroStep(keyCode: 0, down: true, flags: 0, delayMS: 0, label: "A")
    let up = MacroStep(keyCode: 0, down: false, flags: 0, delayMS: 10, label: "A")
    XCTAssertNotNil(MacroValidation.error([]))
    XCTAssertNotNil(MacroValidation.error([down]))
    XCTAssertNotNil(MacroValidation.error([up]))
    XCTAssertNil(MacroValidation.error([down, up]))
    var invalid = up; invalid.delayMS = -1
    XCTAssertNotNil(MacroValidation.error([down, invalid]))
    invalid.delayMS = 60_001
    XCTAssertNotNil(MacroValidation.error([down, invalid]))
  }
  func testTiltAndReport4DecodeWithoutGuessingForMalformedInput() {
    XCTAssertEqual(MouseInputReport.tiltMask([]), [])
    XCTAssertEqual(MouseInputReport.tiltMask([0]), [])
    let left = MouseInputReport.map["BIT_TILT_L"]!, right = MouseInputReport.map["BIT_TILT_R"]!
    XCTAssertEqual(MouseInputReport.tiltMask([UInt8(1 << left)]), [-1])
    XCTAssertEqual(MouseInputReport.tiltMask([UInt8(1 << right)]), [1])
    XCTAssertEqual(MouseInputReport.tiltMask([UInt8((1 << left) | (1 << right))]), [-1, 1])
    XCTAssertEqual(MouseInputReport.report4([4, 0x50]), [])
    XCTAssertEqual(MouseInputReport.report4([4, 0x50, 0x50] + Array(repeating: 0, count: 13)), [0x50])
  }
  @MainActor func testMacrosPersistAndRejectDuplicateActiveBinding() {
    let name = "RazerMouseTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    let input = InputActions(vendorID: 0x1532, live: false, defaults: defaults)
    let steps = [MacroStep(keyCode: 0, down: true, flags: 0, delayMS: 0, label: "A"), MacroStep(keyCode: 0, down: false, flags: 0, delayMS: 20, label: "A")]
    var first = MouseMacro(name: "测试", deviceKey: "device-A", trigger: "button:4", enabled: true, steps: steps)
    XCTAssertTrue(input.save(first))
    var second = first; second.id = UUID()
    XCTAssertFalse(input.save(second))
    second.deviceKey = "device-B"
    XCTAssertTrue(input.save(second))
    let restored = InputActions(vendorID: 0x1532, live: false, defaults: defaults)
    XCTAssertEqual(restored.macros.count, 2)
    XCTAssertFalse(restored.macrosEnabled, "Reconnect/launch must never auto-enable input actions")
    first.enabled = false; XCTAssertTrue(input.save(first))
    input.delete(first.id); XCTAssertEqual(input.macros.count, 1)
  }
  @MainActor func testLightingPlanUsesEveryCompatibleTargetZoneAndSkipsUnsupported() {
    let model = MouseModel(monitoring: false); model.installPreview("lighting")
    let first = model.devices[0]
    var second = first; second.id = "second"
    second.attributes += ["scroll_matrix_effect_static", "left_matrix_effect_static"]
    var third = first; third.id = "third"; third.attributes = ["matrix_effect_spectrum"]
    let zone = LightZone.zones(first).first { $0.name == "标志" }!
    let plan = LightingPlan.writes(devices: [first, second, third], selected: first.id, zone: zone, effect: "static", targets: [second.id, third.id])
    XCTAssertEqual(plan.filter { $0.deviceID == first.id }.count, 1)
    XCTAssertEqual(plan.filter { $0.deviceID == second.id }.count, 3)
    XCTAssertFalse(plan.contains { $0.deviceID == third.id })
    XCTAssertTrue(LightingPlan.writes(devices: [first], selected: first.id, zone: zone, effect: "blinking", targets: []).isEmpty)
    XCTAssertEqual(LightingPlan.payload(effect: "breath", color: [1, 2, 3], second: [4, 5, 6], mode: 2, speed: 1), Data([1, 2, 3, 4, 5, 6]))
    XCTAssertEqual(LightingPlan.payload(effect: "reactive", color: [1, 2, 3], second: [], mode: 1, speed: 3), Data([3, 1, 2, 3]))
  }
}
