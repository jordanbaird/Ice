//
//  HotkeyRecorder.swift
//  Ice
//

import SwiftUI

/// A view that records user-chosen key combinations for a hotkey.
struct HotkeyRecorder<Label: View>: View {
    @StateObject private var model: HotkeyRecorderModel
    @State private var frame: CGRect = .zero
    @State private var isInsideSegment2 = false
    @State private var timer: Timer?

    private let label: Label

    private var modifierString: String {
        model.section?.hotkey?.modifiers.stringValue ?? ""
    }

    private var keyString: String {
        guard let key = model.section?.hotkey?.key else {
            return ""
        }
        return key.stringValue.capitalized
    }

    private var symbolString: String {
        if model.isRecording {
            return "escape"
        }
        if model.isEnabled {
            return "xmark.circle.fill"
        }
        return "record.circle"
    }

    private var segment1HelpString: String {
        if model.isRecording {
            return ""
        }
        if model.isEnabled {
            return "Click to record new hotkey"
        }
        return "Click to record hotkey"
    }

    private var segment2HelpString: String {
        if model.isRecording {
            return "Cancel recording"
        }
        if model.isEnabled {
            return "Delete hotkey"
        }
        return "Click to record hotkey"
    }

    /// Creates a hotkey recorder that records user-chosen key
    /// combinations for the given section.
    ///
    /// - Parameters:
    ///   - section: The menu bar section whose hotkey is recorded.
    ///   - label: A label for the recorder.
    init(section: MenuBarSection?, @ViewBuilder label: () -> Label) {
        let model = HotkeyRecorderModel(section: section)
        self._model = StateObject(wrappedValue: model)
        self.label = label()
    }

    var body: some View {
        LabeledContent {
            HStack(spacing: 1) {
                segment1
                segment2
            }
            .frame(width: 130, height: 21)
            .onFrameChange(update: $frame)
            .error(model.failure)
            .buttonStyle(.custom)
        } label: {
            label
        }
        .onChange(of: model.failure) { _, newValue in
            timer?.invalidate()
            if newValue != nil {
                timer = .scheduledTimer(
                    withTimeInterval: 3,
                    repeats: false
                ) { _ in
                    model.failure = nil
                }
            }
        }
    }

    @ViewBuilder
    private var segment1: some View {
        Button {
            model.startRecording()
        } label: {
            segment1Label
                .frame(maxWidth: .infinity)
        }
        .help(segment1HelpString)
        .customButtonConfiguration {
            $0.shape = .leadingSegment
            $0.isHighlighted = model.isRecording
        }
    }

    @ViewBuilder
    private var segment2: some View {
        Button {
            if model.isRecording {
                model.stopRecording()
            } else if model.isEnabled {
                model.section?.hotkey = nil
            } else {
                model.startRecording()
            }
        } label: {
            Color.clear
                .overlay { segment2Label }
        }
        .frame(width: frame.height)
        .onHover { isInside in
            isInsideSegment2 = isInside
        }
        .help(segment2HelpString)
        .customButtonConfiguration {
            $0.shape = .trailingSegment
        }
    }

    @ViewBuilder
    private var segment1Label: some View {
        if model.isRecording {
            if isInsideSegment2 {
                Text("Cancel")
            } else if !model.pressedModifierStrings.isEmpty {
                HStack(spacing: 1) {
                    ForEach(model.pressedModifierStrings, id: \.self) { string in
                        Text(string)
                            .frame(width: frame.height - 2)
                            .background { keyCap }
                    }
                }
            } else {
                Text("Type Hotkey")
            }
        } else if model.isEnabled {
            HStack(spacing: 0) {
                Text(modifierString)
                Text(keyString)
            }
        } else {
            Text("Record Hotkey")
        }
    }

    @ViewBuilder
    private var segment2Label: some View {
        Image(systemName: symbolString)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .padding(2)
    }

    @ViewBuilder
    private var keyCap: some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(.background.opacity(0.5))
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .inset(by: -2)
                    .offset(y: -2)
                    .strokeBorder(.background.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .shadow(
                color: .black.opacity(0.25),
                radius: 1
            )
            .frame(
                width: frame.height - 2,
                height: frame.height - 2
            )
    }
}

#Preview {
    HotkeyRecorder(section: nil) {
        EmptyView()
    }
    .padding()
}
