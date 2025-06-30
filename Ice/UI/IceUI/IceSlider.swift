//
//  IceSlider.swift
//  Ice
//

import CompactSlider
import SwiftUI

struct IceSlider<Value: BinaryFloatingPoint, ValueLabel: View, ValueLabelSelectability: TextSelectability>: View {
    private let value: Binding<Value>
    private let bounds: ClosedRange<Value>
    private let step: Value
    private let valueLabel: ValueLabel
    private let valueLabelSelectability: ValueLabelSelectability

    init(
        value: Binding<Value>,
        in bounds: ClosedRange<Value> = 0...1,
        step: Value = 0,
        valueLabelSelectability: ValueLabelSelectability = .disabled,
        @ViewBuilder valueLabel: () -> ValueLabel
    ) {
        self.value = value
        self.bounds = bounds
        self.step = step
        self.valueLabel = valueLabel()
        self.valueLabelSelectability = valueLabelSelectability
    }

    init(
        _ valueLabelKey: LocalizedStringKey,
        valueLabelSelectability: ValueLabelSelectability = .disabled,
        value: Binding<Value>,
        in bounds: ClosedRange<Value> = 0...1,
        step: Value = 0
    ) where ValueLabel == Text {
        self.init(
            value: value,
            in: bounds,
            step: step,
            valueLabelSelectability: valueLabelSelectability
        ) {
            Text(valueLabelKey)
        }
    }

    private var borderShape: some InsettableShape {
        if #available(macOS 26.0, *) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
        } else {
            RoundedRectangle(cornerRadius: 5, style: .circular)
        }
    }

    var body: some View {
        CompactSlider(
            value: value,
            in: bounds,
            step: step,
            handleVisibility: .hovering(width: 1),
            minHeight: 0
        ) {
            valueLabel
                .textSelection(valueLabelSelectability)
                .frame(height: 22)
        }
        .compactSliderDisabledHapticFeedback(true)
        .clipShape(borderShape)
        .contentShape([.interaction, .focusEffect], borderShape)
    }
}
