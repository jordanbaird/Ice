//
//  HotkeyRecorderModel.swift
//  Ice
//

import Cocoa
import Combine
import OSLog
import SwiftUI

class HotkeyRecorderModel: ObservableObject {
    @Published private(set) var isRecording = false

    @Published private(set) var pressedModifierStrings = [String]()

    @Published var failure: HotkeyRecordingFailure?

    @Published var hotkey: Hotkey

    private var monitor: LocalEventMonitor?

    private weak var appState: AppState?

    init(hotkey: Hotkey) {
        self.hotkey = hotkey
    }

    func assignAppState(_ appState: AppState) {
        guard self.appState == nil else {
            Logger.hotkeyRecorderModel.warning("Multiple attempts made to assign AppState")
            return
        }
        self.appState = appState
        guard !appState.isPreview else {
            return
        }
        monitor = LocalEventMonitor(mask: [.keyDown, .flagsChanged]) { [weak self] event in
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

    /// Disables the hotkey and starts monitoring for events.
    func startRecording() {
        guard !isRecording else {
            return
        }
        isRecording = true
        hotkey.disable()
        monitor?.start()
        pressedModifierStrings.removeAll()
    }

    /// Enables the hotkey and stops monitoring for events.
    func stopRecording() {
        guard isRecording else {
            return
        }
        isRecording = false
        monitor?.stop()
        hotkey.enable()
        pressedModifierStrings.removeAll()
        failure = nil
    }

    private func handleFailure(_ failure: HotkeyRecordingFailure) {
        // remove the modifier strings so the pressed modifiers
        // aren't being displayed at the same time as a failure
        pressedModifierStrings.removeAll()
        self.failure = failure
    }

    private func handleKeyDown(event: NSEvent) {
        let keyCombination = KeyCombination(event: event)
        if keyCombination.modifiers.isEmpty {
            if keyCombination.key == .escape {
                // escape was pressed with no modifiers
                stopRecording()
            } else {
                handleFailure(.noModifiers)
            }
            return
        }
        if keyCombination.modifiers == .shift {
            handleFailure(.onlyShift)
            return
        }
        if keyCombination.isReservedBySystem {
            handleFailure(.reserved(keyCombination))
            return
        }
        // if we made it this far, all checks passed; assign the
        // new key combination and stop recording
        hotkey.keyCombination = keyCombination
        stopRecording()
    }

    private func handleFlagsChanged(event: NSEvent) {
        pressedModifierStrings = Modifiers.canonicalOrder.compactMap {
            event.modifierFlags.contains($0.nsEventFlags) ? $0.symbolicValue : nil
        }
    }
}

// MARK: - Logger

private extension Logger {
    static let hotkeyRecorderModel = Logger(category: "HotkeyRecorderModel")
}
