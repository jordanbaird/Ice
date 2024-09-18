//
//  HotkeyRecorderModel.swift
//  Ice
//

import Combine
import SwiftUI

@MainActor
final class HotkeyRecorderModel: ObservableObject {
    @EnvironmentObject private var appState: AppState

    @Published private(set) var isRecording = false

    @Published var isPresentingReservedByMacOSError = false

    let hotkey: Hotkey

    private lazy var monitor = LocalEventMonitor(mask: .keyDown) { [weak self] event in
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
        guard !keyCombination.isReservedBySystem else {
            isPresentingReservedByMacOSError = true
            return
        }
        hotkey.keyCombination = keyCombination
        stopRecording()
    }
}
