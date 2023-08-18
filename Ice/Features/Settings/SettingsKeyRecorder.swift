//
//  SettingsKeyRecorder.swift
//  Ice
//

import SwiftKeys
import SwiftUI

private class SettingsKeyRecorderModel: ObservableObject {
    @Published var keyCommand: KeyCommand
    @Published var size: CGSize = .zero
    @Published var isRecording = false {
        didSet {
            if isRecording {
                keyCommand.disable()
                keyDownMonitor?.start()
            } else {
                keyDownMonitor?.stop()
                keyCommand.enable()
            }
        }
    }

    private var keyDownMonitor: LocalEventMonitor?

    init(name: KeyCommand.Name) {
        self.keyCommand = KeyCommand(name: name)
        self.keyCommand.enable()
        self.keyDownMonitor = LocalEventMonitor(mask: .keyDown) { [weak self] event in
            guard let self else {
                return event
            }
            handleKeyDown(event: event)
            return nil
        }
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
        keyCommand.key = key
        keyCommand.modifiers = modifiers
        isRecording = false
    }
}

struct SettingsKeyRecorder: View {
    @StateObject private var model: SettingsKeyRecorderModel

    private var modifiersString: String {
        model.keyCommand.modifiers
            .reduce(into: "") { $0.append($1.stringValue) }
    }

    private var keyString: String? {
        guard let key = model.keyCommand.key else {
            return nil
        }
        if key == .space {
            return "Space"
        }
        return key.stringValue.localizedCapitalized
    }

    init(name: KeyCommand.Name) {
        let model = SettingsKeyRecorderModel(name: name)
        self._model = StateObject(wrappedValue: model)
    }

    var body: some View {
        HStack(spacing: 1) {
            segment1
            segment2
        }
        .frame(width: 160, height: 24)
        .background {
            GeometryReader { proxy in
                Color.clear.onAppear {
                    model.size = proxy.size
                }
            }
        }
    }

    private var segment1: some View {
        Button {
            model.isRecording = true
        } label: {
            Group {
                if model.isRecording {
                    Text("Type Hotkey")
                } else if
                    model.keyCommand.isEnabled,
                    let keyString
                {
                    HStack {
                        Text(modifiersString)
                        Text(keyString)
                    }
                } else {
                    Text("Record Hotkey")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(SettingsButtonStyle(flattenedEdges: .trailing))
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
            Color.clear.overlay {
                if model.isRecording {
                    Image(systemName: "escape")
                } else if model.keyCommand.isEnabled {
                    Image(systemName: "xmark.circle.fill")
                } else {
                    Image(systemName: "record.circle")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: model.size.height)
        .buttonStyle(SettingsButtonStyle(flattenedEdges: .leading))
    }
}

struct SettingsKeyRecorder_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            SettingsKeyRecorder(name: .toggle(.hidden))
                .previewDisplayName("Hidden")
            SettingsKeyRecorder(name: .toggle(.alwaysHidden))
                .previewDisplayName("Always Hidden")
        }
        .padding()
        .buttonStyle(SettingsButtonStyle())
    }
}
