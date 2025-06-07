//
//  MenuBarAppearanceManager.swift
//  Ice
//

import AXSwift
import Cocoa
import Combine
import Foundation

/// A manager for the appearance of the menu bar.
@MainActor
final class MenuBarAppearanceManager: ObservableObject, BindingExposable {
    /// The current menu bar appearance configuration.
    @Published var configuration: MenuBarAppearanceConfigurationV2 = .defaultConfiguration

    /// The currently previewed partial configuration.
    @Published var previewConfiguration: MenuBarAppearancePartialConfiguration?

    /// The current CFString AX Notification of mission control
    @Published var missionControl: CFString = .kAXExposeExit {
        didSet {
            if missionControl == .kAXExposeShowAllWindows || missionControl == .kAXExposeShowFrontWindows {
                hideOverlaypanels = true
            } else {
                hideOverlaypanels = false
            }
        }
    }
    @Published var hideOverlaypanels: Bool = false

    /// The shared app state.
    private weak var appState: AppState?

    /// UserDefaults values crap
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    /// The currently managed menu bar overlay panels.
    private(set) var overlayPanels: [String: MenuBarOverlayPanel] = [:]

    /// The pid of Dock
    @Published var dockPid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock")[0]
        .processIdentifier

    /// The amount to inset the menu bar if called for by the configuration.
    let menuBarInsetAmount: CGFloat = 5

    /// Creates a manager with the given app state.
    init(appState: AppState) {
        self.appState = appState
    }

    /// Performs initial setup of the manager.
    func performSetup() {
        loadInitialState()
        configureCancellables()
    }

    /// Loads the initial values for the configuration.
    private func loadInitialState() {
        do {
            if let data = Defaults.data(forKey: .menuBarAppearanceConfigurationV2) {
                configuration = try decoder.decode(MenuBarAppearanceConfigurationV2.self, from: data)
            }
        } catch {
            Logger.appearanceManager.error("Error decoding configuration: \(error)")
        }
    }

    /// Configures the internal observers for the manager.
    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .sink { [weak self] _ in
                guard let self else { return }
                configureOverlayPanels(with: configuration)
                Bridging.getCurrentSpaces().forEach { self.overlayPanels[$0]?.insertUpdateFlag(.applicationMenuFrame) }
            }
            .store(in: &c)

        NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .debounce(for: 0.1, scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                print("screen config update")
                configureOverlayPanels(with: configuration, reset: true)
            }
            .store(in: &c)

        // - MARK:
        // Update when light/dark mode changes.
        DistributedNotificationCenter.default()
            .publisher(for: DistributedNotificationCenter.interfaceThemeChangedNotification)
            .debounce(for: 0.1, scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                Bridging.getCurrentSpaces().forEach {
                    guard let currentPanel = self?.overlayPanels[$0] else { return }
                    currentPanel.updateTaskContext.setTask(for: .desktopWallpaper, timeout: .seconds(5)) {
                        while true {
                            try Task.checkCancellation()
                            currentPanel.insertUpdateFlag(.desktopWallpaper)
                            try await Task.sleep(for: .seconds(1))
                        }
                    }
                }
            }
            .store(in: &c)
        

        // Update application menu frame when the menu bar owning or frontmost app changes.
        Publishers.Merge(
            NSWorkspace.shared.publisher(for: \.frontmostApplication, options: .old)
                .combineLatest(NSWorkspace.shared.publisher(for: \.frontmostApplication, options: .new))
                .compactMap { old, new in old == new ? nil : old },
            NSWorkspace.shared.publisher(for: \.menuBarOwningApplication, options: .old)
                .combineLatest(NSWorkspace.shared.publisher(for: \.menuBarOwningApplication, options: .new))
                .compactMap { old, new in old == new ? nil : old }
        )
        .removeDuplicates()
        .sink { [weak self] _ in
            guard let self, let appState else { return }
            Bridging.getCurrentSpaces().forEach { spaceID in
                
                guard let currentPanel = self.overlayPanels[spaceID] else { return }
                let displayID = currentPanel.owningScreen.displayID
                currentPanel.updateTaskContext.setTask(for: .applicationMenuFrame, timeout: .seconds(5)) {
                    var hasDoneInitialUpdate = false
                    while true {
                        try Task.checkCancellation()
                        guard
                            appState.menuBarManager.getApplicationMenuFrame(for: displayID)
                                != currentPanel.applicationMenuFrame
                        else {
                            try await Task.sleep(for: .milliseconds(50))
                            continue
                        }
                        if Bridging.getCurrentSpaces().contains(spaceID) {
                            currentPanel.insertUpdateFlag(.applicationMenuFrame)
                        }
                        hasDoneInitialUpdate = true
                    }
                }
                Task {
                    try? await Task.sleep(for: .milliseconds(100))
                    if currentPanel.owningScreen != NSScreen.main {
                        currentPanel.updateTaskContext.cancelTask(for: .applicationMenuFrame)
                    }
                }
            }
        }
        .store(in: &c)

        // Props to Yabai
        // Note that we don't use AXSwift because it doesn't have the custom notifications and I don't feel like modifying it
        $dockPid
            .removeDuplicates()
            .sink { pid in
                sleep(1)
                let customPort = Port()
                RunLoop.current.add(customPort, forMode: .default)
                let thread = Thread {
                    var observer: AXObserver!
                    let element: AXUIElement = AXUIElementCreateApplication(pid)
                    AXObserverCreate(pid, updateExposeStatus, &observer)
                    [
                        CFString.kAXExposeExit, .kAXExposeShowAllWindows, .kAXExposeShowFrontWindows,
                        .kAXExposeShowDesktop,
                    ].forEach { notification in
                        AXObserverAddNotification(observer, element, notification, nil)
                    }
                    CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
                    RunLoop.current.run()
                }
                thread.start()
            }
            .store(in: &c)

        appState?.menuBarManager.$isMenuBarHiddenBySystem
            .sink { [weak self] isHidden in
                self?.overlayPanels.values.forEach { $0.alphaValue = isHidden ? 0 : 1 }
            }
            .store(in: &c)

        // Random stuff to make sure everything updates if detection fails
        Timer.publish(every: 3, on: .main, in: .default)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                Bridging.getCurrentSpaces().map { self.overlayPanels[$0] }.forEach {
                    $0?.insertUpdateFlag(.desktopWallpaper)
                    $0?.insertUpdateFlag(.applicationMenuFrame)
                }
                Set(self.overlayPanels.keys).subtracting(Bridging.getAllSpaces()).forEach {
                    self.overlayPanels[$0]?.close()
                    self.overlayPanels.removeValue(forKey: $0)
                    print("Removing overlay for removed space")
                }
                self.dockPid =
                    NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock")[0]
                    .processIdentifier
            }
            .store(in: &c)

        $configuration
            .encode(encoder: encoder)
            .receive(on: DispatchQueue.main)
            .sink { completion in
                if case .failure(let error) = completion {
                    Logger.appearanceManager.error("Error encoding configuration: \(error)")
                }
            } receiveValue: { data in
                Defaults.set(data, forKey: .menuBarAppearanceConfigurationV2)
            }
            .store(in: &c)

        $configuration
            .throttle(for: 0.1, scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] configuration in
                guard let self else { return }
                // The overlay panels may not have been configured yet. Since some of the
                // properties on the manager might call for them, try to configure now.
                if overlayPanels.isEmpty {
                    configureOverlayPanels(with: configuration)
                }
            }
            .store(in: &c)

        cancellables = c
    }

    /// Returns a Boolean value that indicates whether a set of overlay panels
    /// is needed for the given configuration.
    private func needsOverlayPanels(for configuration: MenuBarAppearanceConfigurationV2) -> Bool {
        let current = configuration.current
        if current.hasShadow || current.hasBorder || configuration.shapeKind != .none || current.tintKind != .none {
            return true
        }
        return false
    }

    /// Configures the manager's overlay panels, if required by the given configuration.
    private func configureOverlayPanels(with configuration: MenuBarAppearanceConfigurationV2, reset: Bool = false) {
        guard let appState, needsOverlayPanels(for: configuration), !reset
        else {
            for key in overlayPanels.keys {
                overlayPanels[key]?.close()
                overlayPanels.removeValue(forKey: key)
            }
            return
        }

        for index in 0..<NSScreen.screens.count {
            let screen = NSScreen.screens[index]
            let currentSpace = Bridging.getCurrentSpace(for: index)
            if overlayPanels[currentSpace] != nil { return }
            let panel = MenuBarOverlayPanel(appState: appState, owningScreen: screen, onSpace: currentSpace)
            panel.needsShow = true
            overlayPanels[currentSpace] = panel
        }
    }

    func setMissionControl(_ value: CFString) {
        missionControl = value
    }
}

// MARK: - Logger
extension Logger {
    /// The logger to use for the menu bar appearance manager.
    fileprivate static let appearanceManager = Logger(category: "MenuBarAppearanceManager")
}

// MARK: - Redirect the AX Notification
func updateExposeStatus(
    _ observer: AXObserver,
    _ element: AXUIElement,
    _ notification: CFString,
    _ refcon: UnsafeMutableRawPointer?
) {
    Task {
        await AppState.shared.appearanceManager.setMissionControl(notification)
    }
}

// Props to Yabai
extension CFString {
    static var kAXExposeShowAllWindows = "AXExposeShowAllWindows" as CFString
    static var kAXExposeShowFrontWindows = "AXExposeShowFrontWindows" as CFString
    static var kAXExposeShowDesktop = "AXExposeShowDesktop" as CFString
    static var kAXExposeExit = "AXExposeExit" as CFString
}
