//
//  IceSlider.swift
//  Ice
//

import CompactSlider
import SwiftUI

struct IceSlider<Value: BinaryFloatingPoint, ValueLabel: View>: View {
    @Binding private var value: Value

    private let bounds: ClosedRange<Value>
    private let step: Value?
    private let valueLabel: ValueLabel

    init(
        value: Binding<Value>,
        in bounds: ClosedRange<Value>,
        step: Value? = nil,
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
        step: Value? = nil
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
        CompactSlider(value: $value, in: bounds, step: step ?? 0)
            .frame(height: height)
            .overlay {
                valueLabel
                    .frame(height: height)
                    .allowsHitTesting(false)
            }
            .compactSliderHandleStyle(.hidden())
            .compactSliderOptionsByAdding(.snapToSteps)
            .compactSliderOptionsByRemoving(.scrollWheel, .enabledHapticFeedback)
            .compactSliderProgress { configuration in
                Rectangle().fill(
                    configuration.focusState.isFocused
                        ? Color.accentColor.opacity(0.75)
                        : Color.accentColor.opacity(0.5)
                )
            }
            .clipShape(borderShape)
            .contentShape([.interaction, .focusEffect], borderShape)
    }
}
