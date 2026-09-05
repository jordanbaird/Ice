//
//  IceSlider.swift
//  Ice
//

import SwiftUI

struct IceSlider<Value: BinaryFloatingPoint, ValueLabel: View>: View where Value.Stride: BinaryFloatingPoint {
    @Binding private var value: Value

    private let bounds: ClosedRange<Value>
    private let step: Value.Stride?
    private let valueLabel: ValueLabel

    init(
        value: Binding<Value>,
        in bounds: ClosedRange<Value>,
        step: Value.Stride? = nil,
        @ViewBuilder valueLabel: () -> ValueLabel
    ) {
        self._value = value
        self.bounds = bounds
        self.step = step
        self.valueLabel = valueLabel()
    }

    init(
        _ valueLabelKey: LocalizedStringKey,
        value: Binding<Value>,
        in bounds: ClosedRange<Value>,
        step: Value.Stride? = nil
    ) where ValueLabel == Text {
        self._value = value
        self.bounds = bounds
        self.step = step
        self.valueLabel = Text(valueLabelKey)
    }

    private var borderShape: some InsettableShape {
        if #available(macOS 26.0, *) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
        } else {
            RoundedRectangle(cornerRadius: 5, style: .circular)
        }
    }

    private var height: CGFloat {
        if #available(macOS 26.0, *) { 24 } else { 22 }
    }

    var body: some View {
        ZStack {
            borderShape
                .fill(.quaternary)

            Group {
                if let step {
                    Slider(value: $value, in: bounds, step: step)
                } else {
                    Slider(value: $value, in: bounds)
                }
            }
            .labelsHidden()
            .controlSize(.small)
            .padding(.horizontal, 4)

            valueLabel
                .frame(height: height)
                .allowsHitTesting(false)
        }
        .frame(height: height)
        .clipShape(borderShape)
        .contentShape([.interaction, .focusEffect], borderShape)
    }
}
