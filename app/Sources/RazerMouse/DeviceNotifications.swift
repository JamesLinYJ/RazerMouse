// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import IOKit
import IOKit.hid

/// Registry notifications only: this observer never opens a HID device or reads input reports.
final class DeviceNotifications {
  private var port: IONotificationPortRef?
  private var iterators: [io_iterator_t] = []
  private let changed: () -> Void

  init(vendorID: UInt16, changed: @escaping () -> Void) throws {
    self.changed = changed
    guard let port = IONotificationPortCreate(kIOMainPortDefault) else {
      throw CocoaError(.coderInvalidValue)
    }
    self.port = port
    IONotificationPortSetDispatchQueue(port, .main)
    for notification in [kIOFirstMatchNotification, kIOTerminatedNotification] {
      let matching = [kIOProviderClassKey: kIOHIDDeviceKey,
        kIOPropertyMatchKey: [kIOHIDVendorIDKey: NSNumber(value: vendorID)]] as CFDictionary
      var iterator: io_iterator_t = 0
      let result = IOServiceAddMatchingNotification(
        port, notification, matching,
        { context, iterator in
          guard let context else { return }
          let observer = Unmanaged<DeviceNotifications>.fromOpaque(context).takeUnretainedValue()
          if DeviceNotifications.drain(iterator) { observer.changed() }
        }, Unmanaged.passUnretained(self).toOpaque(), &iterator)
      guard result == KERN_SUCCESS else {
        throw NSError(domain: NSMachErrorDomain, code: Int(result))
      }
      iterators.append(iterator)
      // Draining the initial iterator arms future notifications without inventing a plug event.
      _ = Self.drain(iterator)
    }
  }
  private static func drain(_ iterator: io_iterator_t) -> Bool {
    var changed = false
    while case let service = IOIteratorNext(iterator), service != 0 {
      changed = true
      IOObjectRelease(service)
    }
    return changed
  }
  deinit {
    for iterator in iterators { IOObjectRelease(iterator) }
    if let port { IONotificationPortDestroy(port) }
  }
}
