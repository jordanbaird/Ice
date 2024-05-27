//
//  HotkeyRecorderModel.swift
//  Ice
//

import Cocoa
import Combine
import OSLog
import SwiftUI

class HotkeyRecorderModel: ObservableObject {
    enum RecordingError: LocalizedError, Hashable {
        case reservedBySystem

        var errorDescription: String? {
            switch self {
            case .reservedBySystem:
                "Hotkey is reserved by macOS"
            }
        }
    }

    @Published private(set) var isRecording = false

    @Published var presentedError: RecordingError? {
        didSet {
            if presentedError != nil {
                isPresentingError = true
            }
        }
    }

    @Published var isPresentingError = false {
        didSet {
            if !isPresentingError {
                presentedError = nil
            }
        }
    }

    let hotkey: Hotkey

    private var monitor: LocalEventMonitor?

    private var cancellables = Set<AnyCancellable>()

    private weak var appState: AppState? {
        didSet {
            guard appState?.isPreview == false else {
                monitor = nil
                return
            }
            monitor = LocalEventMonitor(mask: .keyDown) { [weak self] event in
                guard let self else {
                    return event
                }
                handleKeyDown(event: event)
                return nil
            }
        }
    }

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

    func assignAppState(_ appState: AppState) {
        guard self.appState == nil else {
            Logger.hotkeyRecorderModel.warning("Multiple attempts made to assign AppState")
            return
        }
        self.appState = appState
    }

    /// Disables the hotkey and starts monitoring for events.
    func startRecording() {
        guard !isRecording else {
            return
        }
        hotkey.disable()
        monitor?.start()
        isRecording = true
    }

    /// Enables the hotkey and stops monitoring for events.
    func stopRecording() {
        guard isRecording else {
            return
        }
        monitor?.stop()
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
        guard !keyCombination.isReservedBySystem else {
            presentedError = .reservedBySystem
            return
        }
        // if we made it this far, all checks passed; assign the
        // new key combination and stop recording
        hotkey.keyCombination = keyCombination
        stopRecording()
    }
}

// MARK: - Logger
private extension Logger {
    static let hotkeyRecorderModel = Logger(category: "HotkeyRecorderModel")
}
