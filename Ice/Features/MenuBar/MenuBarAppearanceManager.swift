//
//  MenuBarAppearanceManager.swift
//  Ice
//

import CoreImage.CIFilterBuiltins
import Cocoa
import Combine
import OSLog

// MARK: - MenuBarAppearanceManager

class MenuBarAppearanceManager: ObservableObject {
    @Published var tint: CGColor?

    private(set) weak var menuBar: MenuBar?

    private lazy var overlayPanel = MenuBarOverlayPanel(appearanceManager: self)

    private var cancellables = Set<AnyCancellable>()

    init(menuBar: MenuBar) {
        self.menuBar = menuBar
        if let dictionary = UserDefaults.standard.dictionary(forKey: Defaults.menuBarTint) {
            do {
                self.tint = try DictionaryDecoder().decode(CodableColor.self, from: dictionary).cgColor
            } catch {
                Logger.appearanceManager.error("Error decoding color: \(error.localizedDescription)")
            }
        }
        configureCancellables()
    }

    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        $tint
            .receive(on: DispatchQueue.main)
            .sink { [weak self] tint in
                guard let self else {
                    return
                }
                if let tint {
                    do {
                        let dictionary = try DictionaryEncoder().encode(CodableColor(cgColor: tint))
                        UserDefaults.standard.set(dictionary, forKey: Defaults.menuBarTint)
                        overlayPanel.show()
                    } catch {
                        Logger.appearanceManager.error("Error encoding color: \(error.localizedDescription)")
                        overlayPanel.hide()
                    }
                } else {
                    UserDefaults.standard.removeObject(forKey: Defaults.menuBarTint)
                    overlayPanel.hide()
                }
            }
            .store(in: &c)

        cancellables = c
    }
}

// MARK: - MenuBarOverlayPanel

private class MenuBarOverlayPanel: NSPanel {
    private static let defaultAlphaValue = 0.2

    private(set) weak var appearanceManager: MenuBarAppearanceManager?

    private var cancellables = Set<AnyCancellable>()

    init(appearanceManager: MenuBarAppearanceManager) {
        super.init(
            contentRect: .zero,
            styleMask: [
                .borderless,
                .fullSizeContentView,
                .nonactivatingPanel,
            ],
            backing: .buffered,
            defer: false
        )
        self.appearanceManager = appearanceManager
        self.title = "Menu Bar Overlay"
        self.level = .statusBar
        self.collectionBehavior = [
            .fullScreenNone,
            .ignoresCycle,
        ]
        self.ignoresMouseEvents = true
        configureCancellables()
    }

    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        appearanceManager?.$tint
            .receive(on: DispatchQueue.main)
            .sink { [weak self] tint in
                self?.backgroundColor = tint.map { NSColor(cgColor: $0) } ?? .clear
            }
            .store(in: &c)

        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else {
                    return
                }
                hide()
                if appearanceManager?.tint != nil {
                    show()
                }
            }
            .store(in: &c)

        cancellables = c
    }

    func show() {
        guard !ProcessInfo.processInfo.isPreview else {
            return
        }
        guard let screen = NSScreen.main else {
            Logger.appearanceManager.info("No screen")
            return
        }
        setFrame(
            CGRect(
                x: screen.frame.minX,
                y: screen.visibleFrame.maxY + 1,
                width: screen.frame.width,
                height: (screen.frame.height - screen.visibleFrame.height) - 1
            ),
            display: true
        )
        let isVisible = isVisible
        if !isVisible {
            alphaValue = 0
        }
        orderFrontRegardless()
        if !isVisible {
            animator().alphaValue = Self.defaultAlphaValue
        }
    }

    func hide() {
        orderOut(nil)
    }
}

// MARK: - Logger
private extension Logger {
    static let appearanceManager = mainSubsystem(category: "MenuBarAppearanceManager")
}
