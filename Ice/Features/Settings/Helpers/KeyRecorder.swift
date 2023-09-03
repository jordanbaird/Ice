//
//  KeyRecorder.swift
//  Ice
//

import SwiftKeys
import SwiftUI

private class KeyRecorderModel: ObservableObject {
    /// The key command managed by the model.
    @Published var keyCommand: KeyCommand?

    /// A Boolean value that indicates whether the key recorder
    /// is currently recording.
    @Published private(set) var isRecording = false

    /// The currently pressed modifiers when the key recorder
    /// is recording. Empty if the key recorder is not recording.
    @Published var pressedModifiers = [KeyCommand.Modifier]()

    /// Local event monitor that listens for key down events and
    /// modifier flag changes.
    private var monitor: LocalEventMonitor?

    /// Canonically ordered mapping between SwiftKeys modifiers
    /// and NSEvent modifier flags.
    private let modifierMapping: KeyValuePairs<KeyCommand.Modifier, NSEvent.ModifierFlags> = [
        .control: .control,
        .option: .option,
        .shift: .shift,
        .command: .command,
    ]

    /// A Boolean value that indicates whether the key command
    /// is currently enabled.
    var isEnabled: Bool {
        keyCommand?.isEnabled ?? false
    }

    /// Creates a model for a key recorder that records user-chosen
    /// key combinations for a key command with the given name.
    init(name: KeyCommand.Name?) {
        self.keyCommand = name.map { KeyCommand(name: $0) }
        guard !ProcessInfo.processInfo.isPreview else {
            return
        }
        self.keyCommand?.enable()
        self.monitor = LocalEventMonitor(mask: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self else {
                return event
            }
            switch event.type {
            case .keyDown:
                handleKeyDown(event: event)
            case .flagsChanged:
                handleFlagsChanged(event: event)
            default:
                return event
            }
            return nil
        }
    }

    /// Disables the key command and starts monitoring for events.
    func startRecording() {
        guard !isRecording else {
            return
        }
        isRecording = true
        keyCommand?.disable()
        monitor?.start()
        pressedModifiers.removeAll()
    }

    /// Enables the key command and stops monitoring for events.
    func stopRecording() {
        guard isRecording else {
            return
        }
        isRecording = false
        monitor?.stop()
        keyCommand?.enable()
        pressedModifiers.removeAll()
    }

    /// Converts the given event's modifier flags into an array
    /// of canonically ordered SwiftKeys modifiers.
    private func modifiers(for event: NSEvent) -> [KeyCommand.Modifier] {
        modifierMapping.compactMap {
            event.modifierFlags.contains($0.value) ? $0.key : nil
        }
    }

    /// Handles local key down events when the key recorder
    /// is recording.
    private func handleKeyDown(event: NSEvent) {
        // convert the event's key code into a SwiftKeys key
        guard let key = KeyCommand.Key(rawValue: Int(event.keyCode)) else {
            NSSound.beep()
            return
        }
        let modifiers = modifiers(for: event)
        guard !modifiers.isEmpty else {
            if key == .escape {
                // escape was pressed with no modifiers;
                // cancel recording
                stopRecording()
            } else {
                // at least one modifier key is required
                // TODO: alert the user of the error
                NSSound.beep()
            }
            return
        }
        guard modifiers != [.shift] else {
            // shift by itself can't be used as a modifier key
            // TODO: alert the user of the error
            NSSound.beep()
            return
        }
        guard !KeyCommand.isReservedBySystem(key: key, modifiers: modifiers) else {
            // key command is reserved by the system
            // TODO: alert the user of the error
            NSSound.beep()
            return
        }
        // if we made it this far, all checks passed; assign the
        // new key and modifiers and stop recording
        keyCommand?.key = key
        keyCommand?.modifiers = modifiers
        stopRecording()
    }

    /// Handles live modifier flag changes when the key recorder
    /// is recording.
    private func handleFlagsChanged(event: NSEvent) {
        pressedModifiers = modifiers(for: event)
    }
}

/// A view that records user-chosen key combinations for a key command.
struct KeyRecorder: View {
    @StateObject private var model: KeyRecorderModel
    @State private var frame: CGRect = .zero
    @State private var isInsideSegment2 = false

    /// Creates a key recorder that records user-chosen key combinations
    /// for a key command with the given name.
    init(name: KeyCommand.Name?) {
        let model = KeyRecorderModel(name: name)
        self._model = StateObject(wrappedValue: model)
    }

    var body: some View {
        HStack(spacing: 1) {
            segment1
            segment2
        }
        .frame(width: 160, height: 24)
        .onFrameChange(update: $frame)
    }

    private var segment1: some View {
        Button {
            model.startRecording()
        } label: {
            segment1Label
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .help(segment1HelpString)
        .settingsButtonID(.leadingSegment)
    }

    private var segment2: some View {
        Button {
            if model.isRecording {
                model.stopRecording()
            } else if model.isEnabled {
                model.keyCommand?.key = nil
                model.keyCommand?.modifiers.removeAll()
            } else {
                model.startRecording()
            }
        } label: {
            Color.clear
                .overlay(
                    Image(systemName: symbolString)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .padding(3)
                )
        }
        .frame(width: frame.height)
        .onHover { isInside in
            isInsideSegment2 = isInside
        }
        .help(segment2HelpString)
        .settingsButtonID(.trailingSegment)
    }

    @ViewBuilder
    private var segment1Label: some View {
        if model.isRecording {
            if isInsideSegment2 {
                Text("Cancel")
            } else if !model.pressedModifiers.isEmpty {
                HStack(spacing: 1) {
                    ForEach(model.pressedModifiers, id: \.self) { modifier in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(.background.opacity(0.5))
                            .aspectRatio(1, contentMode: .fit)
                            .overlay(Text(modifier.stringValue))
                    }
                }
            } else {
                Text("Type Hotkey")
            }
        } else if model.isEnabled {
            HStack {
                Text(modifiersString)
                Text(keyString)
            }
        } else {
            Text("Record Hotkey")
        }
    }

    private var modifiersString: String {
        model.keyCommand?.modifiers.lazy
            .map { $0.stringValue }
            .joined() ?? ""
    }

    private var keyString: String {
        guard let key = model.keyCommand?.key else {
            return ""
        }
        if key == .space {
            return "Space"
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
}

struct KeyRecorder_Previews: PreviewProvider {
    static var previews: some View {
        KeyRecorder(
            name: .toggle(
                section: StatusBarSection(
                    name: "",
                    controlItem: ControlItem()
                )
            )
        )
        .padding()
        .buttonStyle(SettingsButtonStyle())
    }
}
