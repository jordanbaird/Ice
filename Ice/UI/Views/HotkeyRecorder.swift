//
//  HotkeyRecorder.swift
//  Ice
//

import Combine
import SwiftUI

// MARK: - HotkeyRecorder

struct HotkeyRecorder<Label: View>: View {
    @StateObject private var model: HotkeyRecorderModel

    private let label: Label

    init(hotkey: Hotkey, @ViewBuilder label: () -> Label) {
        self._model = StateObject(wrappedValue: HotkeyRecorderModel(hotkey: hotkey))
        self.label = label()
    }

    var body: some View {
        IceLabeledContent {
            segmentStack
        } label: {
            label
        }
        .alert(
            "Hotkey is reserved by macOS",
            isPresented: $model.isPresentingSystemReservedError
        ) {
            Button("OK") {
                model.isPresentingSystemReservedError = false
            }
        }
    }

    @ViewBuilder
    private var segmentStack: some View {
        HStack(spacing: 1) {
            leadingSegment
            trailingSegment
        }
        .frame(width: 132, height: 24)
    }

    @ViewBuilder
    private var leadingSegment: some View {
        Button {
            if model.isRecording {
                model.stopRecording()
            } else {
                model.startRecording()
            }
        } label: {
            leadingSegmentLabel
        }
        .buttonStyle(
            HotkeyRecorderButtonStyle(
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
            HotkeyRecorderButtonStyle(
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
                Text(keyCombination.displayValue)
            } else {
                Text("ERROR")
            }
        } else {
            Text("Record Hotkey")
        }
    }

    @ViewBuilder
    private var trailingSegmentLabel: some View {
        let (name, label, padding) = if model.isRecording {
            ("escape", "Cancel", 6.0)
        } else if model.hotkey.isEnabled {
            ("xmark", "Clear", 7.5)
        } else {
            ("record.circle", "Record", 5.5)
        }
        Image(systemName: name)
            .resizable()
            .aspectRatio(1, contentMode: .fit)
            .padding(padding)
            .accessibilityLabel(label)
    }
}

// MARK: - HotkeyRecorderModel

@MainActor
private final class HotkeyRecorderModel: ObservableObject {
    @EnvironmentObject private var appState: AppState

    @Published private(set) var isRecording = false

    @Published var isPresentingSystemReservedError = false

    let hotkey: Hotkey

    private lazy var monitor = EventMonitor.local(for: .keyDown) { [weak self] event in
        guard let self else {
            return event
        }
        handleKeyDown(event: event)
        return nil
    }

    private var cancellables = Set<AnyCancellable>()

    init(hotkey: Hotkey) {
        self.hotkey = hotkey
        configureCancellables()
    }

    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        hotkey.objectWillChange
            .sink { [weak self] in
                self?.objectWillChange.send()
            }
            .store(in: &c)

        cancellables = c
    }

    func startRecording() {
        guard !isRecording else {
            return
        }
        hotkey.disable()
        monitor.start()
        isRecording = true
    }

    func stopRecording() {
        guard isRecording else {
            return
        }
        monitor.stop()
        hotkey.enable()
        isRecording = false
    }

    private func handleKeyDown(event: NSEvent) {
        let keyCombination = KeyCombination(event: event)
        guard !keyCombination.modifiers.isEmpty else {
            if keyCombination.key == .escape {
                stopRecording()
            } else {
                NSSound.beep()
            }
            return
        }
        guard keyCombination.modifiers != .shift else {
            NSSound.beep()
            return
        }
        guard !keyCombination.isSystemReserved else {
            isPresentingSystemReservedError = true
            return
        }
        hotkey.keyCombination = keyCombination
        stopRecording()
    }
}

// MARK: - HotkeyRecorderButtonStyle

private struct HotkeyRecorderButtonStyle: ButtonStyle {
    enum Segment {
        case leading
        case trailing
    }

    var segment: Segment
    var isHighlighted: Bool

    private var radii: RectangleCornerRadii {
        let r: CGFloat = if #available(macOS 26.0, *) { 6 } else { 5 }
        return switch segment {
        case .leading: RectangleCornerRadii(topLeading: r, bottomLeading: r)
        case .trailing: RectangleCornerRadii(bottomTrailing: r, topTrailing: r)
        }
    }

    private var borderShape: some InsettableShape {
        if #available(macOS 26.0, *) {
            UnevenRoundedRectangle(cornerRadii: radii, style: .continuous)
        } else {
            UnevenRoundedRectangle(cornerRadii: radii, style: .circular)
        }
    }

    func makeBody(configuration: Configuration) -> some View {
        let isProminent = configuration.isPressed != isHighlighted
        borderShape
            .fill(isProminent ? .tertiary : .quaternary)
            .opacity(isProminent ? 0.5 : 0.75)
            .overlay {
                configuration.label
                    .lineLimit(1)
                    .foregroundStyle(.primary)
            }
            .contentShape([.interaction, .focusEffect], borderShape)
    }
}
