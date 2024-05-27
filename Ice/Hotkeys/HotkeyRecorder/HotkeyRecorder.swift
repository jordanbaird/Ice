//
//  HotkeyRecorder.swift
//  Ice
//

import SwiftUI

struct HotkeyRecorder<Label: View>: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var model: HotkeyRecorderModel
    @State private var frame: CGRect = .zero

    private let label: Label

    private var symbolString: String {
        if model.isRecording {
            "escape"
        } else if model.hotkey.isEnabled {
            "xmark.circle.fill"
        } else {
            "record.circle"
        }
    }

    init(hotkey: Hotkey, @ViewBuilder label: () -> Label) {
        let model = HotkeyRecorderModel(hotkey: hotkey)
        self._model = StateObject(wrappedValue: model)
        self.label = label()
    }

    var body: some View {
        LabeledContent {
            HStack(spacing: 1) {
                leadingSegment
                trailingSegment
            }
            .frame(width: 130, height: 22)
            .onFrameChange(update: $frame)
            .alert(
                model.presentedError?.localizedDescription ?? "",
                isPresented: $model.isPresentingError
            ) {
                Button("OK") {
                    model.isPresentingError = false
                }
            }
        } label: {
            label
        }
        .task {
            model.assignAppState(appState)
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
        .frame(width: frame.height)
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
            }
        } else {
            Text("Record Hotkey")
        }
    }

    @ViewBuilder
    private var trailingSegmentLabel: some View {
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
        UnevenRoundedRectangle(cornerRadii: radii)
            .foregroundStyle(Color.primary) // explicitly specify `Color.primary`
            .opacity(isHighlighted || isPressed ? 0.2 : 0.1)
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
