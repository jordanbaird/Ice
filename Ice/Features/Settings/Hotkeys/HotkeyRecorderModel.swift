//
//  HotkeyRecorderModel.swift
//  Ice
//

import Cocoa
import Combine

/// Model for a hotkey recorder's state.
class HotkeyRecorderModel: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var pressedModifierStrings = [String]()
    @Published var failure: RecordingFailure?

    let section: MenuBarSection?

    private let handleFailure: (HotkeyRecorderModel, RecordingFailure) -> Void
    private var monitor: LocalEventMonitor?

    private var cancellables = Set<AnyCancellable>()

    /// A Boolean value that indicates whether the hotkey is
    /// currently enabled.
    var isEnabled: Bool {
        section?.hotkeyIsEnabled ?? false
    }

    /// Creates a model for a hotkey recorder that records key
    /// combinations for the given section's hotkey.
    init(section: MenuBarSection?) {
        defer {
            configureCancellables()
        }
        self.section = section
        self.handleFailure = { model, failure in
            // remove the modifier strings so the pressed modifiers
            // aren't being displayed at the same time as a failure
            model.pressedModifierStrings.removeAll()
            model.failure = failure
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

    deinit {
        stopRecording()
    }

    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        if let section {
            section.$hotkey
                .sink { [weak self] _ in
                    self?.objectWillChange.send()
                }
                .store(in: &c)
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
        failure = nil
    }

    /// Handles local key down events when the hotkey recorder
    /// is recording.
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

    /// Handles modifier flag changes when the hotkey recorder
    /// is recording.
    private func handleFlagsChanged(event: NSEvent) {
        pressedModifierStrings = Hotkey.Modifiers.canonicalOrder.compactMap {
            event.modifierFlags.contains($0.nsEventFlags) ? $0.stringValue : nil
        }
    }
}
