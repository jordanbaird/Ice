//
//  HotkeyRecorder.swift
//  Ice
//

import Combine
import SwiftUI

/// Model for a hotkey recorder's state.
private class HotkeyRecorderModel: ObservableObject {
    /// An alias for a type that describes the reason why recording
    /// a hotkey failed.
    typealias FailureReason = HotkeyRecorder.FailureReason

    /// Retained observers to help manage the state of the model.
    private var cancellables = Set<AnyCancellable>()

    /// The section managed by the model.
    let section: StatusBarSection?

    /// A Boolean value that indicates whether the hotkey recorder
    /// is currently recording.
    @Published private(set) var isRecording = false

    /// Strings representing the currently pressed modifiers when the
    /// hotkey recorder is recording. Empty if the hotkey recorder is
    /// not recording.
    @Published private(set) var pressedModifierStrings = [String]()

    /// A closure that handles recording failures.
    private let handleFailure: (HotkeyRecorderModel, FailureReason) -> Void

    /// Local event monitor that listens for key down events and
    /// modifier flag changes.
    private var monitor: LocalEventMonitor?

    /// A Boolean value that indicates whether the hotkey is
    /// currently enabled.
    var isEnabled: Bool { section?.hotkeyIsEnabled ?? false }

    /// Creates a model for a hotkey recorder that records user-chosen
    /// key combinations for the given section's hotkey.
    init(section: StatusBarSection?, onFailure: @escaping (FailureReason) -> Void) {
        defer {
            configureCancellables()
        }
        self.section = section
        self.handleFailure = { model, failureReason in
            // immediately remove the modifier strings, before the failure
            // handler is even performed; it looks weird to have the pressed
            // modifiers displayed in the hotkey recorder at the same time
            // as a failure
            model.pressedModifierStrings.removeAll()
            onFailure(failureReason)
        }
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

    /// Sets up a series of observers to respond to important changes
    /// in the model's state.
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

    /// Handles local key down events when the hotkey recorder is recording.
    private func handleKeyDown(event: NSEvent) {
        // convert the event's key code and modifiers
        let key = Hotkey.Key(rawValue: Int(event.keyCode))
        let modifiers = Hotkey.Modifiers(nsEventFlags: event.modifierFlags)
        if modifiers.isEmpty {
            if key == .escape {
                // cancel when escape is pressed with no modifiers
                stopRecording()
            } else {
                // require at least one modifier
                handleFailure(self, .emptyModifiers)
            }
            return
        }
        if modifiers == .shift {
            // shift can't be the only modifier
            handleFailure(self, .onlyShift)
            return
        }
        let hotkey = Hotkey(key: key, modifiers: modifiers)
        if Hotkey.isReservedBySystem(key: key, modifiers: modifiers) {
            // hotkey is reserved by the system
            handleFailure(self, .systemReserved(hotkey))
            return
        }
        // if we made it this far, all checks passed; assign the
        // new hotkey and stop recording
        section?.hotkey = hotkey
        stopRecording()
    }

    /// Handles modifier flag changes when the hotkey recorder is recording.
    private func handleFlagsChanged(event: NSEvent) {
        pressedModifierStrings = Hotkey.Modifiers.canonicalOrder.compactMap {
            event.modifierFlags.contains($0.nsEventFlags) ? $0.stringValue : nil
        }
    }
}

/// A view that records user-chosen key combinations for a hotkey.
struct HotkeyRecorder: View {
    /// A type that describes the reason why recording a hotkey failed.
    enum FailureReason: Hashable {
        case emptyModifiers
        case onlyShift
        case systemReserved(Hotkey)

        /// Message to display to the user when recording fails.
        var message: String {
            switch self {
            case .emptyModifiers:
                return "Hotkey must include at least one modifier."
            case .onlyShift:
                return "Shift cannot be a hotkey's only modifier."
            case .systemReserved(let hotkey):
                return "\"\(hotkey.stringValue)\" is reserved system-wide."
            }
        }
    }

    /// The model that manages the hotkey recorder.
    @StateObject private var model: HotkeyRecorderModel

    /// The hotkey recorder's frame.
    @State private var frame: CGRect = .zero

    /// A Boolean value that indicates whether the mouse is currently
    /// inside the bounds of the hotkey recorder's second segment.
    @State private var isInsideSegment2 = false

    /// Creates a hotkey recorder that records user-chosen key
    /// combinations for the given section.
    init(section: StatusBarSection?, onFailure: @escaping (FailureReason) -> Void) {
        let model = HotkeyRecorderModel(section: section, onFailure: onFailure)
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
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
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
                Text(modifierString)
                Text(keyString)
            }
        } else {
            Text("Record Hotkey")
        }
    }

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
}

struct HotkeyRecorder_Previews: PreviewProvider {
    static var previews: some View {
        HotkeyRecorder(section: nil) { _ in }
            .padding()
            .buttonStyle(SettingsButtonStyle())
    }
}
