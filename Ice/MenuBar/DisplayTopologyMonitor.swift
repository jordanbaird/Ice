//
//  DisplayTopologyMonitor.swift
//  Ice
//

import AppKit
import Combine
import OSLog

/// Reacts when displays are connected, disconnected, rearranged or when the
/// main display changes (see ``DisplayTopology``).
@MainActor
final class DisplayTopologyMonitor {
    private weak var appState: AppState?
    private var cancellables = Set<AnyCancellable>()
    private var lastDisplays = [DisplayTopology.Display]()
    private let logger = Logger(category: "DisplayTopologyMonitor")

    func performSetup(with appState: AppState) {
        self.appState = appState
        lastDisplays = Self.currentDisplays()
        NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .debounce(for: 0.3, scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleChange()
            }
            .store(in: &cancellables)
    }

    /// The connected displays, with their stable UUIDs.
    static func currentDisplays() -> [DisplayTopology.Display] {
        NSScreen.screens.compactMap { screen in
            guard let uuid = screen.displayUUIDString else {
                return nil
            }
            return DisplayTopology.Display(
                uuid: uuid,
                frame: screen.frame,
                isBuiltIn: CGDisplayIsBuiltin(screen.displayID) != 0,
                isMain: screen.displayID == CGMainDisplayID()
            )
        }
    }

    private func handleChange() {
        guard let appState else {
            return
        }
        let current = Self.currentDisplays()
        let change = DisplayTopology.diff(old: lastDisplays, new: current)
        lastDisplays = current

        let panel = appState.menuBarManager.iceBarPanel
        let reactions = DisplayTopology.reactions(to: change, barDisplayUUID: nil)
        guard !reactions.isEmpty else {
            return
        }
        logger.notice("Display change: +\(change.added.count, privacy: .public) -\(change.removed.count, privacy: .public) main:\(change.mainChanged, privacy: .public) reconfigured:\(change.reconfigured.count, privacy: .public)")

        // Close the bar (and the section really presented) if its display is
        // gone. The identity was captured when the show began, so this works
        // even if the panel's `screen` is already nil or remapped.
        panel.reconcileConnectedDisplays()
        // Inline sections have no bar: reconcile every section's cycle too.
        appState.menuBarManager.reconcileSectionsWithDisplays()
        if reactions.contains(.recache) {
            Task {
                await appState.itemManager.cacheItemsRegardless()
            }
        }
    }
}
