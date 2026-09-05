// Standalone AppKit hypothesis probe; NOT part of the Ice application target.
// Compile (SDK 27):
//   xcrun swiftc -parse-as-library Tests/NativeZeroWidthBoundaryProbe.swift -o <probe>
// Package as a separate .app with its own bundle identifier before manual QA.
// Quit Ice and other status-item probes first; this probe never controls them.
//
// Hypothesis, NOT established by compilation: replacing a boundary's native
// NSStatusBarButton with a plain NSView may allow a genuinely zero-width item
// to remain registered, preserving its native order without a blank slot.
// SDK 27 NSStatusItem.h declares `view` as a public, non-deprecated property
// that displays a view instead of `button` (API_AVAILABLE macos 10.0).
// It does NOT promise a zero minimum width or retained placement at zero width.
//
// Only four probe-owned items exist: Left 2, Left 1, blank boundary, Z arrow.
// The blank boundary stays isVisible=true until termination. Each arrow action
// synchronously changes BOTH item.length and view.frame.width between zero and
// a bounded overflow width. No AX, input tap, synthesized input, timers,
// animation, private attributes, or direct preference writes are used.
// Autosave names are unique per run, so prior probe positions are not reused.
// Optional --hide-view-when-expanded is a separate hypothesis: hide only the
// boundary's NSView while keeping its status item registered. This must still
// pass the same real no-slot/rapid-toggle checks; NSView.isHidden is not proof.
//
// Manual acceptance (must be observed, not inferred from logged requests):
// 1. Check actual order and spacing: Left 2, Left 1, boundary, Z arrow. Expanded
//    must have no empty 16/17-point slot between Left 1 and the arrow.
// 2. Click the arrow: both left items must disappear immediately, with the
//    arrow remaining at its original right-hand position. Click again: return
//    immediately, preserving order and gap-free spacing.
// 3. Rapidly click 12 times, then 11 times; each action should visibly toggle
//    and final state follow parity, with no delayed reopen or extra slot.
// 4. Expanded, Command-drag only Left 1 across the arrow in both directions.
//    Hiding should follow physical placement without changing the arrow state
//    during the drag. Other apps and the clock must retain native behavior.
// 5. Test display/Space changes and crowding separately before considering any
//    production use. A requested zero width is not proof the host uses zero.
// Right-click the Z arrow and choose Quit Probe to remove only these four items.

import AppKit

@MainActor
final class NativeZeroWidthBoundaryProbe: NSObject, NSApplicationDelegate {
    private let runID = UUID().uuidString
    private let arrowWidth: CGFloat = 32
    private var items = [NSStatusItem]()
    private var boundary: NSStatusItem?
    private var boundaryView: NSView?
    private var arrow: NSStatusItem?
    private var isHidden = false
    private var actionCount = 0
    private let hidesExpandedView = CommandLine.arguments.contains("--hide-view-when-expanded")

    func applicationDidFinishLaunching(_ notification: Notification) {
        let arrow = makeItem(name: "Arrow", length: arrowWidth)
        self.arrow = arrow
        if let button = arrow.button {
            button.target = self
            button.action = #selector(activateArrow)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityIdentifier("Ice.ZeroWidthProbe.Arrow")
            button.setAccessibilityLabel("Zero-width boundary probe")
        }

        let boundary = makeItem(name: "Boundary", length: 0)
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 0, height: NSStatusBar.system.thickness))
        view.autoresizingMask = []
        view.setAccessibilityElement(false)
        view.isHidden = hidesExpandedView
        boundary.view = view
        boundary.length = 0
        boundary.isVisible = true
        self.boundary = boundary
        boundaryView = view

        for name in ["Left 1", "Left 2"] {
            let item = makeItem(name: name, length: NSStatusItem.variableLength)
            item.button?.title = name
            item.button?.setAccessibilityIdentifier("Ice.ZeroWidthProbe.\(name)")
            item.button?.setAccessibilityLabel("Zero-width probe \(name)")
        }

        updateArrow()
        log("Ready. Hypothesis is unverified. Check actual zero-width spacing and native order; right-click Z arrow to quit.")
        logGeometryNextTurn()
    }

    private func makeItem(name: String, length: CGFloat) -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: length)
        item.autosaveName = "Ice.ZeroWidthProbe.\(runID).\(name)"
        items.append(item)
        return item
    }

    @objc private func activateArrow() {
        guard let button = arrow?.button else { return }
        // Consider only a fresh event delivered to our own arrow window. An
        // accessibility action may have no mouse event and still toggles.
        if let event = NSApp.currentEvent,
           event.windowNumber == button.window?.windowNumber,
           [.leftMouseUp, .rightMouseUp].contains(event.type),
           (0 ..< 0.5).contains(ProcessInfo.processInfo.systemUptime - event.timestamp) {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard !flags.contains(.command) else { return }
            if event.type == .rightMouseUp || flags.contains(.control) {
                showMenu(button: button)
                return
            }
        }
        toggle()
    }

    @objc private func toggle() {
        guard let boundary, let boundaryView,
              let screen = arrow?.button?.window?.screen ?? NSScreen.main else { return }
        isHidden.toggle()
        actionCount += 1
        // Stay inside the native status region. Oversized status items can be
        // discarded on macOS 27; this is intentionally not a huge-width probe.
        let regionWidth = screen.auxiliaryTopRightArea?.width ?? (screen.frame.width - 300)
        let width = isHidden ? max(32, regionWidth - arrowWidth) : 0
        boundary.length = width
        boundaryView.setFrameSize(NSSize(width: width, height: NSStatusBar.system.thickness))
        boundaryView.isHidden = hidesExpandedView && !isHidden
        updateArrow()
        log("Action \(actionCount): \(isHidden ? "hidden" : "expanded"); requested width=\(width); isVisible=\(boundary.isVisible)")
        logGeometryNextTurn()
    }

    private func updateArrow() {
        arrow?.button?.title = isHidden ? "Z ◂" : "Z ▸"
        arrow?.button?.toolTip = "Zero-width probe — \(isHidden ? "show" : "hide") Left 1/2; right-click to quit"
    }

    private func showMenu(button: NSStatusBarButton) {
        let menu = NSMenu()
        let toggleItem = NSMenuItem(
            title: isHidden ? "Show Probe Items" : "Hide Probe Items",
            action: #selector(toggle), keyEquivalent: ""
        )
        toggleItem.target = self
        menu.addItem(toggleItem)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Probe", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY), in: button)
    }

    private func logGeometryNextTurn() {
        // Diagnostic reads only. Width/state changes above never wait for this.
        DispatchQueue.main.async { [weak self] in
            guard let self, let boundary, let boundaryView else { return }
            log("Geometry: boundary length=\(boundary.length), visible=\(boundary.isVisible), view=\(boundaryView.frame), host=\(String(describing: boundaryView.window?.frame)), arrow=\(String(describing: arrow?.button?.window?.frame))")
        }
    }

    private func log(_ message: String) {
        print(String(format: "%.3f", ProcessInfo.processInfo.systemUptime), message)
        fflush(stdout)
        NSLog("ZeroWidthProbe: %@", message)
    }

    func applicationWillTerminate(_ notification: Notification) {
        for item in items { NSStatusBar.system.removeStatusItem(item) }
        items.removeAll()
        boundary = nil
        boundaryView = nil
        arrow = nil
    }
}

@main
enum NativeZeroWidthBoundaryProbeMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = NativeZeroWidthBoundaryProbe()
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
