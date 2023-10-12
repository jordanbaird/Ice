//
//  MenuBarAppearanceManager.swift
//  Ice
//

import CoreImage.CIFilterBuiltins
import Cocoa
import Combine
import OSLog

class MenuBarAppearanceManager: ObservableObject {
    @Published var tint: CGColor?

    private(set) weak var menuBar: MenuBar?

    private lazy var overlayPanel = MenuBarOverlayPanel(appearanceManager: self)

    private var cancellables = Set<AnyCancellable>()

    init(menuBar: MenuBar) {
        self.menuBar = menuBar
        if let dictionary = UserDefaults.standard.dictionary(forKey: Defaults.menuBarTint) {
            self.tint = try? CodableColor(dictionaryValue: dictionary).cgColor
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
                do {
                    if let tint {
                        let dictionary = try CodableColor(cgColor: tint).dictionaryValue
                        UserDefaults.standard.set(dictionary, forKey: Defaults.menuBarTint)
                    } else {
                        UserDefaults.standard.removeObject(forKey: Defaults.menuBarTint)
                    }
                } catch {
                    Logger.appearanceManager.error("MenuBarAppearanceManager: \(error.localizedDescription)")
                }
                if tint != nil {
                    overlayPanel.show()
                } else {
                    overlayPanel.hide()
                }
            }
            .store(in: &c)

        cancellables = c
    }
}

struct CodableColor {
    var cgColor: CGColor
}

extension CodableColor: Codable {
    enum CodingKeys: CodingKey {
        case components
        case colorSpace
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        guard let components = cgColor.components else {
            throw EncodingError.invalidValue(
                cgColor,
                EncodingError.Context(
                    codingPath: encoder.codingPath,
                    debugDescription: "Missing color components"
                )
            )
        }
        guard let colorSpaceData = cgColor.colorSpace?.copyICCData() else {
            throw EncodingError.invalidValue(
                cgColor,
                EncodingError.Context(
                    codingPath: encoder.codingPath,
                    debugDescription: "Missing or invalid color space"
                )
            )
        }
        try container.encode(components, forKey: .components)
        try container.encode(colorSpaceData as Data, forKey: .colorSpace)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var components = try container.decode([CGFloat].self, forKey: .components)
        let colorSpaceData = try container.decode(Data.self, forKey: .colorSpace) as CFData
        guard let colorSpace = CGColorSpace(iccData: colorSpaceData) else {
            throw DecodingError.dataCorruptedError(
                forKey: .colorSpace,
                in: container, debugDescription: "Cannot decode ICC profile data"
            )
        }
        guard let cgColor = CGColor(colorSpace: colorSpace, components: &components) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Cannot decode color"
                )
            )
        }
        self.cgColor = cgColor
    }
}

extension CodableColor: DictionaryRepresentable { }

private class MenuBarOverlayPanel: NSPanel {
    private static let defaultAlphaValue = 0.2
    private var cancellables = Set<AnyCancellable>()
    private(set) weak var appearanceManager: MenuBarAppearanceManager?

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

private extension Logger {
    static let appearanceManager = mainSubsystem(category: "MenuBarAppearanceManager")
}
