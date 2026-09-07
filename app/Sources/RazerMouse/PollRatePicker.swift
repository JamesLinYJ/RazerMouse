// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

struct PollRatePicker: View {
  @ObservedObject var model: MouseModel
  var body: some View {
    Picker(
      "回报率",
      selection: Binding<UInt32?>(
        get: { model.state?.pollRate },
        set: { if let value = $0 { model.number("poll_rate", value) } }
      )
    ) {
      if model.state?.pollRate == nil { Text("未读取").tag(Optional<UInt32>.none) }
      ForEach(model.info?.pollRates ?? [], id: \.self) { rate in
        Text("\(rate) Hz").tag(Optional(rate))
      }
      if let rate = model.state?.pollRate, model.info?.pollRates.contains(rate) == false {
        Text("\(rate) Hz · 当前读数").tag(Optional(rate))
      }
    }.disabled(model.state?.pollRate == nil)
  }
}
