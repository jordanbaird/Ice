//
//  CaptureIndicatorPanel27.swift
//  Ice
//

import Cocoa
import Combine
import OSLog
import SwiftUI

/// Draws Ice's own camera and microphone indicator on the menu bar.
///
/// macOS has one of its own, but it belongs to Control Centre, and Control Centre's modules are
/// gone from the bar while any assessment assertion is live — which is to say, whenever Ice hides
/// anything. Nothing in the assertion can spare them (measured on macOS 27.0 against every system
/// item number up to 127, Control Centre's bundle identifier and the capturing application's), so
/// the only way to leave the user that indicator is to draw it.
///
/// Clicking it opens Control Centre, where the camera's own controls — Video Effects, Mic Mode —
/// live during a call. Control Centre is the one system item that opens from an Accessibility
/// press while items are concealed, so the click costs no reveal.
@available(macOS 27.0, *)
@MainActor
final class CaptureIndicatorPanel27: NSPanel {
    private let logger = Logger(category: "CaptureIndicatorPanel27")
    private weak var appState: AppState?
    private var cancellables = Set<AnyCancellable>()
    private var hostingView: NSHostingView<CaptureIndicatorView>?

    /// Whether the items were read for this placement, rather than remembered from before.
    private var hasFreshItems = false

    /// Counts the placements asked for, so one overtaken by a later one is dropped.
    private var placementGeneration = 0

    /// How wide the indicator is drawn.
    private static let width: CGFloat = 36

    /// How much room is left between it and the items beside it.
    private static let gap: CGFloat = 6

    private static let frameLock = NSLock()
    nonisolated(unsafe) private static var shownFrame: CGRect?

    /// Where the indicator is drawn right now, for the hit tests that decide whether the pointer
    /// is over an empty stretch of the bar. Without this, hovering the indicator revealed the
    /// hidden items and clicking it did whatever a click on the bare bar does.
    nonisolated static func indicatorFrame() -> CGRect? {
        frameLock.withLock { shownFrame }
    }

    private static func setIndicatorFrame(_ frame: CGRect?) {
        frameLock.withLock { shownFrame = frame }
    }

    init(appState: AppState) {
        self.appState = appState
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.isFloatingPanel = true
        self.level = .statusBar
        self.collectionBehavior = [.fullScreenNone, .ignoresCycle, .canJoinAllSpaces]
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.hidesOnDeactivate = false
        self.animationBehavior = .none
    }

    /// Starts following what is in use and where the bar is.
    ///
    /// The watcher reads the devices every couple of seconds and republishes either way, so the
    /// indicator follows the items along the bar as they come and go without a timer of its own.
    func performSetup(watcher: CaptureWatcher27, concealer: Concealer27) {
        watcher.$kind
            .receive(on: DispatchQueue.main)
            .sink { [weak self] kind in
                MainActor.assumeIsolated {
                    self?.update(kind: kind)
                }
            }
            .store(in: &cancellables)
        // An item shown for a moment appears where the indicator stands, so the indicator leaves
        // at once rather than on the watcher's next reading.
        concealer.$isShowingTemporarily
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak watcher] _ in
                MainActor.assumeIsolated {
                    self?.update(kind: watcher?.kind)
                }
            }
            .store(in: &cancellables)
    }

    /// Shows, moves or hides the indicator.
    private func update(kind: CaptureIndicator27.Kind?) {
        guard
            let kind,
            let appState,
            appState.settings.advanced.showCaptureIndicator,
            appState.concealer27.isConcealing,
            // Only where the hiding takes macOS's own indicator away. With the native switch it
            // stays on the bar, and Ice's would stand beside it.
            appState.concealer27.needsClickLift,
            // Out of the way while an item is shown for a moment: that item is drawn where the
            // indicator stands, and a click meant for it would land on the indicator instead.
            !appState.concealer27.isShowingTemporarily,
            let screen = NSScreen.screenWithActiveMenuBar,
            let menuBarHeight = screen.getMenuBarHeight()
        else {
            if isVisible {
                orderOut(nil)
            }
            Self.setIndicatorFrame(nil)
            return
        }
        if let remaining = appState.concealer27.timeUntilSettled() {
            // The bar is still moving: where the items are now is not where they will be, and
            // placing the indicator against them would put it on top of one. Wait it out.
            Task { [weak self] in
                try? await Task.sleep(for: remaining + .milliseconds(50))
                self?.update(kind: kind)
            }
            return
        }
        if !hasFreshItems {
            // Where the items begin is remembered from the last read of the bar, and the read
            // that followed an item being shown and hidden again has not necessarily happened
            // yet. Coming back on that answer put the indicator where the bar used to begin,
            // further left, and it stepped into place a moment later. Ask for the items first and
            // appear in the right spot.
            placementGeneration += 1
            let generation = placementGeneration
            Task { [weak self] in
                _ = await MenuBarItemProvider27.items()
                guard let self, generation == placementGeneration else {
                    return
                }
                hasFreshItems = true
                defer { hasFreshItems = false }
                update(kind: kind)
            }
            return
        }
        let barFrame = CGRect(
            x: screen.frame.minX,
            y: screen.frame.maxY - menuBarHeight,
            width: screen.frame.width,
            height: menuBarHeight
        )
        let frame = CaptureIndicator27.frame(
            barFrame: barFrame,
            leftEdgeOfItems: MenuBarItemProvider27.leftEdge(for: screen.displayID),
            width: Self.width,
            gap: Self.gap
        )
        let view = CaptureIndicatorView(kind: kind) { [weak self] in
            self?.openCaptureControls()
        }
        if let hostingView {
            hostingView.rootView = view
        } else {
            let hostingView = NSHostingView(rootView: view)
            contentView = hostingView
            self.hostingView = hostingView
        }
        setFrame(frame, display: true)
        Self.setIndicatorFrame(frame)
        if !isVisible {
            orderFrontRegardless()
        }
    }

    /// Opens the camera and microphone controls, the ones the system's own indicator opens.
    ///
    /// The module those belong to is not drawn while anything is concealed, so there is nothing
    /// to press until the concealment is lifted — the same lift a click on the clock needs, and
    /// the same cost: the hidden items flash into view for a moment. Measured on macOS 27.0: with
    /// nothing concealed the module is a system item of its own,
    /// `com.apple.menuextra.audiovideo` ("Audio and Video Controls"), and it opens from an
    /// Accessibility press.
    ///
    /// If it does not appear, Control Centre is opened instead: the same controls are inside it
    /// during a call, and it opens with the concealment still in force.
    private func openCaptureControls() {
        guard let appState else {
            return
        }
        logger.notice("Opening the capture controls from the indicator")
        Task { [weak self] in
            await appState.concealer27.suspendReleased(for: .milliseconds(900))
            for _ in 0..<14 {
                _ = await MenuBarItemProvider27.items()
                if let element = MenuBarItemProvider27.systemItem(withIdentifier: Self.audioVideoItem) {
                    await Self.press(element)
                    // Hide the items again as soon as the controls are open, rather than letting
                    // the lift run its course: what the user sees of it is the whole cost.
                    try? await Task.sleep(for: .milliseconds(150))
                    appState.concealer27.resumeConcealing()
                    return
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
            self?.logger.warning("The audio and video item never appeared, so Control Centre was opened instead")
            if let element = MenuBarItemProvider27.systemItem(withIdentifier: Self.controlCentreItem) {
                await Self.press(element)
            }
            appState.concealer27.resumeConcealing()
        }
    }

    /// The system item the camera and microphone controls belong to.
    private static let audioVideoItem = "com.apple.menuextra.audiovideo"

    /// Control Centre's own item, which holds the same controls during a call.
    private static let controlCentreItem = "com.apple.menuextra.controlcenter"

    /// Presses an Accessibility element off the main thread, which the call can block.
    private static func press(_ element: AXUIElement) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                _ = AXUIElementPerformAction(element, kAXPressAction as CFString)
                continuation.resume()
            }
        }
    }
}

// MARK: - The indicator itself

/// A green camera, or an orange microphone, drawn the way macOS draws its own.
@available(macOS 27.0, *)
private struct CaptureIndicatorView: View {
    let kind: CaptureIndicator27.Kind
    let press: () -> Void

    private var colour: Color {
        switch kind {
        case .camera: Color(red: 0.16, green: 0.78, blue: 0.3)
        case .microphone: Color(red: 0.98, green: 0.58, blue: 0.09)
        }
    }

    private var symbol: String {
        switch kind {
        case .camera: "video.fill"
        case .microphone: "mic.fill"
        }
    }

    var body: some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(colour)
                .frame(width: 30, height: 20)
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture(perform: press)
        .help(kind == .camera ? "The camera is in use" : "The microphone is in use")
    }
}
