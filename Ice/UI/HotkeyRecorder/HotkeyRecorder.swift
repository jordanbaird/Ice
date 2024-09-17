//
//  HotkeyRecorder.swift
//  Ice
//

import SwiftUI

struct HotkeyRecorder<Label: View>: View {
    @StateObject private var model: HotkeyRecorderModel

    private let label: Label

    init(hotkey: Hotkey, @ViewBuilder label: () -> Label) {
        self._model = StateObject(wrappedValue: HotkeyRecorderModel(hotkey: hotkey))
        self.label = label()
    }

    var body: some View {
        IceLabeledContent {
            HStack(spacing: 1) {
                leadingSegment
                trailingSegment
            }
            .frame(width: 130, height: 22)
            .alignmentGuide(.firstTextBaseline) { dimension in
                dimension[VerticalAlignment.center]
            }
        } label: {
            label
                .alignmentGuide(.firstTextBaseline) { dimension in
                    dimension[VerticalAlignment.center]
                }
        }
        .alert(
            "Hotkey is reserved by macOS",
            isPresented: $model.isPresentingReservedByMacOSError
        ) {
            Button("OK") {
                model.isPresentingReservedByMacOSError = false
            }
        }
    }

    @ViewBuilder
    private var leadingSegment: some View {
        Button {
            model.startRecording()
        } label: {
            leadingSegmentLabel
        }
        .buttonStyle(
            HotkeyRecorderSegmentButtonStyle(
                segment: .leading,
                isHighlighted: model.isRecording
            )
        )
    }

    @ViewBuilder
    private var trailingSegment: some View {
        Button {
            if model.isRecording {
                model.stopRecording()
            } else if model.hotkey.isEnabled {
                model.hotkey.keyCombination = nil
            } else {
                model.startRecording()
            }
        } label: {
            trailingSegmentLabel
        }
        .buttonStyle(
            HotkeyRecorderSegmentButtonStyle(
                segment: .trailing,
                isHighlighted: false
            )
        )
        .aspectRatio(1, contentMode: .fit)
    }

    @ViewBuilder
    private var leadingSegmentLabel: some View {
        if model.isRecording {
            Text("Type Hotkey")
        } else if model.hotkey.isEnabled {
            if let keyCombination = model.hotkey.keyCombination {
                HStack(spacing: 0) {
                    Text(keyCombination.modifiers.symbolicValue)
                    Text(keyCombination.key.stringValue.capitalized)
                }
            } else {
                Text("ERROR")
            }
        } else {
            Text("Record Hotkey")
        }
    }

    @ViewBuilder
    private var trailingSegmentLabel: some View {
        let symbolString = if model.isRecording {
            "escape"
        } else if model.hotkey.isEnabled {
            "xmark.circle.fill"
        } else {
            "record.circle"
        }
        Image(systemName: symbolString)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .padding(1)
    }
}

private struct HotkeyRecorderSegmentButtonStyle: PrimitiveButtonStyle {
    enum Segment {
        case leading
        case trailing
    }

    @State private var frame = CGRect.zero
    @State private var isPressed = false

    var segment: Segment
    var isHighlighted: Bool

    private var radii: RectangleCornerRadii {
        switch segment {
        case .leading:
            RectangleCornerRadii(topLeading: 5, bottomLeading: 5)
        case .trailing:
            RectangleCornerRadii(bottomTrailing: 5, topTrailing: 5)
        }
    }

    func makeBody(configuration: Configuration) -> some View {
        UnevenRoundedRectangle(cornerRadii: radii, style: .circular)
            .fill(isHighlighted || isPressed ? .tertiary : .quaternary)
            .overlay {
                configuration.label
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                    .padding(EdgeInsets(top: 3, leading: 8, bottom: 3, trailing: 8))
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isPressed = frame.contains(value.location)
                    }
                    .onEnded { value in
                        isPressed = false
                        if frame.contains(value.location) {
                            configuration.trigger()
                        }
                    }
            )
            .onFrameChange(update: $frame)
    }
}
