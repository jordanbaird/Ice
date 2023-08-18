//
//  KeyRecorder.swift
//  Ice
//

import SwiftKeys
import SwiftUI

// MARK: - KeyRecorderModel

private class KeyRecorderModel: ObservableObject {
    @Published var keyCommand: KeyCommand

    @Published var frame: CGRect = .zero

    @Published var isRecording = false

    private var keyDownMonitor: LocalEventMonitor?

    init(name: KeyCommand.Name) {
        self.keyCommand = KeyCommand(name: name)
        guard !ProcessInfo.processInfo.isPreview else {
            return
        }
        self.keyCommand.enable()
        self.keyDownMonitor = LocalEventMonitor(mask: .keyDown) { [weak self] event in
            guard let self else {
                return event
            }
            handleKeyDown(event: event)
            return nil
        }
    }

    /// Disables the key command and starts monitoring for
    /// key down events.
    func startRecording() {
        objectWillChange.send()
        keyCommand.disable()
        keyDownMonitor?.start()
    }

    /// Enables the key command and stops monitoring for
    /// key down events.
    func stopRecording() {
        objectWillChange.send()
        keyDownMonitor?.stop()
        keyCommand.enable()
    }

    /// Handles key down events for the model's local event monitor.
    private func handleKeyDown(event: NSEvent) {
        guard let key = KeyCommand.Key(rawValue: Int(event.keyCode)) else {
            NSSound.beep()
            return
        }
        let modifiers: [KeyCommand.Modifier] = {
            var modifiers = [KeyCommand.Modifier]()
            if event.modifierFlags.contains(.control) {
                modifiers.append(.control)
            }
            if event.modifierFlags.contains(.option) {
                modifiers.append(.option)
            }
            if event.modifierFlags.contains(.shift) {
                modifiers.append(.shift)
            }
            if event.modifierFlags.contains(.command) {
                modifiers.append(.command)
            }
            return modifiers
        }()
        guard !modifiers.isEmpty else {
            if key == .escape {
                // escape was pressed with no modifiers; cancel recording
                isRecording = false
            } else {
                // TODO: Alert the user that they need to use at least one modifier key
                NSSound.beep()
            }
            return
        }
        guard modifiers != [.shift] else {
            // TODO: Alert the user that shift by itself can't be used as a modifier key
            NSSound.beep()
            return
        }
        guard !KeyCommand.isReservedBySystem(key: key, modifiers: modifiers) else {
            // TODO: Alert the user that the key command is reserved by the system
            NSSound.beep()
            return
        }
        // if we made it this far, all checks passed; assign the new key
        // and modifiers and stop recording
        (keyCommand.key, keyCommand.modifiers) = (key, modifiers)
        isRecording = false
    }
}

// MARK: - KeyRecorder

struct KeyRecorder: View {
    @StateObject private var model: KeyRecorderModel
    @State private var isInsideSegment2 = false

    init(name: KeyCommand.Name) {
        let model = KeyRecorderModel(name: name)
        self._model = StateObject(wrappedValue: model)
    }

    var body: some View {
        HStack(spacing: 1) {
            segment1
            segment2
        }
        .frame(width: 160, height: 24)
        .onFrameChange(update: $model.frame)
        .onChange(of: model.isRecording) { newValue in
            if newValue {
                model.startRecording()
            } else {
                model.stopRecording()
            }
        }
    }

    private var segment1: some View {
        Button {
            model.isRecording = true
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
                model.isRecording = false
            } else if model.keyCommand.isEnabled {
                model.keyCommand.key = nil
                model.keyCommand.modifiers.removeAll()
            } else {
                model.isRecording = true
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
        .frame(width: model.frame.height)
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
            } else {
                Text("Type Hotkey")
            }
        } else if model.keyCommand.isEnabled {
            HStack {
                Text(modifiersString)
                Text(keyString)
            }
        } else {
            Text("Record Hotkey")
        }
    }

    private var modifiersString: String {
        model.keyCommand.modifiers.lazy
            .map { $0.stringValue }
            .joined()
    }

    private var keyString: String {
        guard let key = model.keyCommand.key else {
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
        if model.keyCommand.isEnabled {
            return "xmark.circle.fill"
        }
        return "record.circle"
    }

    private var segment1HelpString: String {
        if model.isRecording {
            return ""
        }
        if model.keyCommand.isEnabled {
            return "Click to record new hotkey"
        }
        return "Click to record hotkey"
    }

    private var segment2HelpString: String {
        if model.isRecording {
            return "Cancel recording"
        }
        if model.keyCommand.isEnabled {
            return "Delete hotkey"
        }
        return "Click to record hotkey"
    }
}

struct KeyRecorder_Previews: PreviewProvider {
    static var previews: some View {
        KeyRecorder(name: .toggle(.hidden))
            .padding()
            .buttonStyle(SettingsButtonStyle())
    }
}
