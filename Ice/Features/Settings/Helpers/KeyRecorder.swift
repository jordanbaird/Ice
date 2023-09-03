//
//  KeyRecorder.swift
//  Ice
//

import Combine
import SwiftUI

private class KeyRecorderModel: ObservableObject {
    private var cancellables = Set<AnyCancellable>()

    /// The section managed by the model.
    let section: StatusBarSection?

    /// A Boolean value that indicates whether the key recorder
    /// is currently recording.
    @Published private(set) var isRecording = false

    /// Strings representing the currently pressed modifiers when
    /// the key recorder is recording. Empty if the key recorder
    /// is not recording.
    @Published private(set) var pressedModifierStrings = [String]()

    /// Local event monitor that listens for key down events and
    /// modifier flag changes.
    private var monitor: LocalEventMonitor?

    /// A Boolean value that indicates whether the hotkey is
    /// currently enabled.
    var isEnabled: Bool { section?.hotkeyIsEnabled ?? false }

    /// Creates a model for a key recorder that records user-chosen
    /// key combinations for the given section's hotkey.
    init(section: StatusBarSection?) {
        defer {
            configureCancellables()
        }
        self.section = section
        guard !ProcessInfo.processInfo.isPreview else {
            return
        }
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

    private func configureCancellables() {
        var c = Set<AnyCancellable>()
        if let section {
            c.insert(section.$hotkey.sink { [weak self] _ in
                self?.objectWillChange.send()
            })
        }
        cancellables = c
    }

    /// Disables the hotkey and starts monitoring for events.
    func startRecording() {
        guard !isRecording else {
            return
        }
        isRecording = true
        section?.disableHotkey()
        monitor?.start()
        pressedModifierStrings = []
    }

    /// Enables the hotkey and stops monitoring for events.
    func stopRecording() {
        guard isRecording else {
            return
        }
        isRecording = false
        monitor?.stop()
        section?.enableHotkey()
        pressedModifierStrings = []
    }

    /// Handles local key down events when the key recorder is recording.
    private func handleKeyDown(event: NSEvent) {
        // convert the event's key code and modifiers
        let key = Hotkey.Key(rawValue: Int(event.keyCode))
        let modifiers = Hotkey.Modifiers(nsEventFlags: event.modifierFlags)
        guard !modifiers.isEmpty else {
            if key == .escape {
                // escape was pressed with no modifiers; cancel recording
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
        // guard !HotKey.isReservedBySystem(key: key, modifiers: modifiers) else {
        //     // hotkey is reserved by the system
        //     // TODO: alert the user of the error
        //     NSSound.beep()
        //     return
        // }
        // if we made it this far, all checks passed; assign the
        // new hotkey and stop recording
        section?.hotkey = Hotkey(key: key, modifiers: modifiers)
        stopRecording()
    }

    /// Handles modifier flag changes when the key recorder is recording.
    private func handleFlagsChanged(event: NSEvent) {
        pressedModifierStrings = Hotkey.Modifiers.canonicalOrder.compactMap {
            event.modifierFlags.contains($0.nsEventFlags) ? $0.stringValue : nil
        }
    }
}

/// A view that records user-chosen key combinations for a hotkey.
struct KeyRecorder: View {
    @StateObject private var model: KeyRecorderModel
    @State private var frame: CGRect = .zero
    @State private var isInsideSegment2 = false

    /// Creates a key recorder that records user-chosen key combinations
    /// for the given section.
    init(section: StatusBarSection?) {
        let model = KeyRecorderModel(section: section)
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
        .settingsButtonShape(.leadingSegment)
        .settingsButtonIsHighlighted(model.isRecording)
    }

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
        .settingsButtonShape(.trailingSegment)
    }

    @ViewBuilder
    private var segment1Label: some View {
        if model.isRecording {
            if isInsideSegment2 {
                Text("Cancel")
            } else if !model.pressedModifierStrings.isEmpty {
                HStack(spacing: 1) {
                    ForEach(model.pressedModifierStrings, id: \.self) { string in
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(.background.opacity(0.5))
                            .aspectRatio(1, contentMode: .fit)
                            .overlay(Text(string))
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
}

struct KeyRecorder_Previews: PreviewProvider {
    static var previews: some View {
        KeyRecorder(section: StatusBarSection(name: "", controlItem: ControlItem()))
            .padding()
            .buttonStyle(SettingsButtonStyle())
    }
}
