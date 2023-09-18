//
//  HotkeyRecorderModel.swift
//  Ice
//

import Cocoa
import Combine

/// Model for a hotkey recorder's state.
class HotkeyRecorderModel: ObservableObject {
    /// An alias for a type that describes a recording failure.
    typealias Failure = HotkeyRecorder.Failure

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
    private let handleFailure: (HotkeyRecorderModel, Failure) -> Void

    /// A closure that removes the failure associated with the
    /// hotkey recorder.
    private let removeFailure: () -> Void

    /// Local event monitor that listens for key down events and
    /// modifier flag changes.
    private var monitor: LocalEventMonitor?

    /// A Boolean value that indicates whether the hotkey is
    /// currently enabled.
    var isEnabled: Bool { section?.hotkeyIsEnabled ?? false }

    /// Creates a model for a hotkey recorder that records user-chosen
    /// key combinations for the given section's hotkey.
    init(
        section: StatusBarSection?,
        onFailure: @escaping (Failure) -> Void,
        removeFailure: @escaping () -> Void
    ) {
        defer {
            configureCancellables()
        }
        self.section = section
        self.handleFailure = { model, failure in
            // immediately remove the modifier strings, before the failure
            // handler is even performed; it looks weird to have the pressed
            // modifiers displayed in the hotkey recorder at the same time
            // as a failure
            model.pressedModifierStrings.removeAll()
            onFailure(failure)
        }
        self.removeFailure = removeFailure
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

    deinit {
        stopRecording()
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
        removeFailure()
    }

    /// Handles local key down events when the hotkey recorder is recording.
    private func handleKeyDown(event: NSEvent) {
        let hotkey = Hotkey(event: event)
        if hotkey.modifiers.isEmpty {
            if hotkey.key == .escape {
                // escape was pressed with no modifiers
                stopRecording()
            } else {
                handleFailure(self, .noModifiers)
            }
            return
        }
        if hotkey.modifiers == .shift {
            handleFailure(self, .onlyShift)
            return
        }
        if hotkey.isReservedBySystem {
            handleFailure(self, .reserved(hotkey))
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
