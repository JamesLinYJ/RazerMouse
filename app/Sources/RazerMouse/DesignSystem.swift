// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

enum MouseStyle {
  static let accent = Color(red: 0.12, green: 0.66, blue: 0.43)
  static let radius: CGFloat = 18
}

struct Glyph: View {
  let name: String
  var size: CGFloat = 18
  var body: some View {
    Image("glyph-" + name, bundle: .module).renderingMode(.template)
      .resizable().scaledToFit().frame(width: size, height: size)
      .accessibilityHidden(true)
  }
}

struct ControlHeading: View {
  let title: String
  let icon: String
  var body: some View {
    HStack(spacing: 7) {
      Glyph(name: icon, size: 15).foregroundStyle(MouseStyle.accent)
      Text(title).font(.system(size: 12, weight: .semibold))
    }
  }
}

struct ControlButtonStyle: ButtonStyle {
  var selected = false
  @Environment(\.isEnabled) private var enabled
  @Environment(\.colorScheme) private var scheme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .foregroundStyle(selected ? MouseStyle.accent : Color.primary.opacity(0.72))
      .padding(.vertical, 8).frame(maxWidth: .infinity)
      .background(
        selected
          ? MouseStyle.accent.opacity(scheme == .dark ? 0.19 : 0.11)
          : Color.primary.opacity(configuration.isPressed ? 0.10 : 0.035),
        in: RoundedRectangle(cornerRadius: 9)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 9)
          .strokeBorder(selected ? MouseStyle.accent.opacity(0.28) : Color.clear, lineWidth: 0.7)
      )
      .opacity(enabled ? 1 : 0.45)
      .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
  }
}

/// Maps the full device range onto a usable slider without assuming a model's DPI ceiling.
enum DpiAdjustment {
  static func value(position: Double, minimum: UInt32, maximum: UInt32, supported: [UInt32])
    -> UInt32
  {
    let bounded = min(Double(maximum), max(Double(minimum), pow(2, position)))
    if !supported.isEmpty {
      return supported.min { abs(Double($0) - bounded) < abs(Double($1) - bounded) } ?? minimum
    }
    return UInt32(bounded.rounded())
  }
}

enum PowerAdjustmentValue {
  static func raw(displayed value: Double, percentage: Bool, minimum: UInt32, maximum: UInt32) -> UInt32? {
    guard value.isFinite else { return nil }
    let scale = percentage ? 100.0 / 255 : 1
    let lower = (Double(minimum) * scale).rounded()
    let upper = (Double(maximum) * scale).rounded()
    guard (lower...upper).contains(value) else { return nil }
    // Percentage labels are rounded. Preserve the valid endpoint when e.g. raw 63 displays as 25%.
    return UInt32(min(Double(maximum), max(Double(minimum), (value / scale).rounded())))
  }
}
