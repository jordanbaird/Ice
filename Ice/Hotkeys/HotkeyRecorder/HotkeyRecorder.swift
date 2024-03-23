//
//  HotkeyRecorder.swift
//  Ice
//

import SwiftUI

struct HotkeyRecorder<Label: View>: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var model: HotkeyRecorderModel
    @State private var frame: CGRect = .zero
    @State private var timer: Timer?

    private let label: Label

    private var modifierString: String {
        model.hotkey.keyCombination?.modifiers.symbolicValue ?? ""
    }

    private var keyString: String {
        model.hotkey.keyCombination?.key.stringValue.capitalized ?? ""
    }

    private var symbolString: String {
        if model.isRecording {
            return "escape"
        }
        if model.hotkey.isEnabled {
            return "xmark.circle.fill"
        }
        return "record.circle"
    }

    private var segment1HelpString: String {
        model.isRecording ? "" : "Click to record"
    }

    private var segment2HelpString: String {
        model.hotkey.isEnabled ? "Delete" : segment1HelpString
    }

    init(hotkey: Hotkey, @ViewBuilder label: () -> Label) {
        let model = HotkeyRecorderModel(hotkey: hotkey)
        self._model = StateObject(wrappedValue: model)
        self.label = label()
    }

    var body: some View {
        LabeledContent {
            HStack(spacing: 1) {
                segment1
                segment2
            }
            .frame(width: 133, height: 24)
            .onFrameChange(update: $frame)
            .overlay(error: model.failure)
            .buttonStyle(.custom)
        } label: {
            label
        }
        .onChange(of: model.failure) { _, newValue in
            timer?.invalidate()
            if newValue != nil {
                timer = .scheduledTimer(withTimeInterval: 3, repeats: false) { _ in
                    model.failure = nil
                }
            }
        }
        .task {
            model.assignAppState(appState)
        }
    }

    @ViewBuilder
    private var segment1: some View {
        Button {
            model.startRecording()
        } label: {
            Color.clear.overlay {
                segment1Label
            }
        }
        .help(segment1HelpString)
        .customButtonConfiguration { configuration in
            configuration.shape = .leadingSegment
            configuration.isHighlighted = model.isRecording
        }
    }

    @ViewBuilder
    private var segment2: some View {
        Button {
            if model.isRecording {
                model.stopRecording()
            } else if model.hotkey.isEnabled {
                model.hotkey.keyCombination = nil
            } else {
                model.startRecording()
            }
        } label: {
            Color.clear.overlay {
                segment2Label
                    .offset(y: 0.5)
            }
        }
        .frame(width: frame.height)
        .help(segment2HelpString)
        .customButtonConfiguration { configuration in
            configuration.shape = .trailingSegment
        }
    }

    @ViewBuilder
    private var segment1Label: some View {
        if model.isRecording {
            if model.pressedModifierStrings.isEmpty {
                Text("Type Hotkey")
            } else {
                HStack(spacing: 1) {
                    ForEach(model.pressedModifierStrings, id: \.self) { string in
                        keyCap(string)
                    }
                }
                .offset(y: 0.5)
            }
        } else if model.hotkey.isEnabled {
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
    private func keyCap(_ label: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4, style: .circular)
                .fill(.background.opacity(0.5))
                .overlay {
                    RoundedRectangle(cornerRadius: 4, style: .circular)
                        .strokeBorder(.foreground.opacity(0.25))
                }
                .shadow(
                    color: .black.opacity(0.25),
                    radius: 1
                )
            Text(label)
                .padding(1)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
