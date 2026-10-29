//
//  IceSlider.swift
//  Ice
//

import SwiftUI

struct IceSlider<Value: BinaryFloatingPoint, ValueLabel: View>: View where Value.Stride == Value {
    private let value: Binding<Value>
    private let bounds: ClosedRange<Value>
    private let step: Value
    private let valueLabel: ValueLabel

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

    init(
        _ valueLabelKey: LocalizedStringKey,
        value: Binding<Value>,
        in bounds: ClosedRange<Value> = 0...1,
        step: Value = 0
    ) where ValueLabel == Text {
        self.init(
            value: value,
            in: bounds,
            step: step
        ) {
            Text(valueLabelKey)
        }
    }

    var body: some View {
        HStack {
            slider
            valueLabel
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var slider: some View {
        if step == 0 {
            Slider(value: value, in: bounds)
        } else {
            Slider(value: value, in: bounds, step: step)
        }
    }
}
