//
//  IceSlider.swift
//  Ice
//

import CompactSlider
import SwiftUI

struct IceSlider<Value: BinaryFloatingPoint, ValueLabel: View>: View {
    let value: Binding<Value>
    let bounds: ClosedRange<Value>
    let step: Value
    let valueLabel: ValueLabel

    init(
        value: Binding<Value>,
        in bounds: ClosedRange<Value> = 0...1,
        step: Value = 0,
        @ViewBuilder valueLabel: () -> ValueLabel
    ) {
        self.value = value
        self.bounds = bounds
        self.step = step
        self.valueLabel = valueLabel()
    }

    var body: some View {
        CompactSlider(
            value: value,
            in: bounds,
            step: step,
            handleVisibility: .hovering(width: 1)
        ) {
            valueLabel
        }
        .compactSliderDisabledHapticFeedback(true)
    }
}
