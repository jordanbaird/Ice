// Standalone AppKit experiment, NOT part of the Ice application target.
// Compile with: xcrun swiftc -parse-as-library Tests/NativeSingleItemToggleProbe.swift -o <probe>
// Package in a separate .app with its own bundle identifier before manual QA.
// Quit Ice before testing; this probe must never manipulate Ice or another app.
//
// Device result, 2026-09-05: REJECTED, not integrated into production Ice.
// A: imageRight/imageHugsTitle=false; B: transparent padded image. With the
// region-minus-32 width, both hid the left test items but also lost the arrow.
// C/D: limiting width to the item's own expanded trailing edge and available
// space, including native-padding/one-slot deductions, still left only the
// system overflow chevrons, not the probe arrow. This source retains the last
// padded-image experiment for diagnosis; it is not a working hiding design.
// The separate zero-width custom-view probe could hide items but retained an
// approximately 16-point expanded gap, so that alternative was also rejected.
// Both status-item probes have been quit. See the dated rapid-toggle review.
//
// Design constraints:
// - Three probe-owned status items only; one toggle and two left-side test items.
// - The toggle itself grows/shrinks synchronously. No second boundary, timer,
//   AX query, input tap, synthetic input, permission request or animation.
// - Keep the native NSStatusBarButton. Native image alignment and then a padded
//   template image were tested as right-edge placement candidates; neither
//   kept a usable arrow visible after widening in this device test.
// - A real mouse action is accepted only inside the rightmost 32-point slot.
//   AXPress has no required mouse event. Command-click remains native reordering.
// - Autosave names are unique to this launch; no production preferences are read
//   or written. Termination removes only this probe's own NSStatusItems.
//
// Intended acceptance matrix (NOT passed; retained for future experiments):
// 1. Order the probe-owned items as Left 2, Left 1, arrow. Click the arrow once:
//    both left items disappear and the arrow stays at the same right-hand point.
// 2. Click again: both return, with no empty placeholder or extra slot.
// 3. Click 12 times rapidly, then 11 times. Every click must visibly change state;
//    final state must follow parity, with no animation, late reopen or jump.
// 4. Click/right-click the blank part of a widened item: no toggle/menu. Right-
//    click its arrow: only the probe menu. Verify no full-width highlight flashes.
// 5. AXPress the arrow in both states. Check that its accessible identity and
//    activation remain usable despite the native button's wide reported frame.
// 6. Expanded: Command-drag Left 1 across the arrow in each direction. Hiding
//    must follow physical order; Command-drag itself must not toggle the probe.
// 7. Other apps and the clock keep their own native left/right click behavior.
// 8. Verify notched/non-notched displays, display/Space changes, and right-side
//    crowding. A capped requested width is not proof MenuBarAgent accepted it.

import AppKit

@MainActor
final class NativeSingleItemToggleProbe: NSObject, NSApplicationDelegate {
    private let iconSlotWidth: CGFloat = 32
    private let runID = UUID().uuidString
    private var items = [NSStatusItem]()
    private var toggleItem: NSStatusItem?
    private var isHidden = false
    private var actionCount = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = makeItem(name: "Toggle", length: iconSlotWidth)
        toggleItem = item
        if let button = item.button {
            button.title = ""
            button.imagePosition = .imageOnly
            button.imageHugsTitle = true
            button.imageScaling = .scaleNone
            button.alignment = .right
            // Suppress a full-width pressed bezel; the glyph itself changes state.
            (button.cell as? NSButtonCell)?.highlightsBy = []
            button.setAccessibilityLabel("Single-item hiding probe")
            button.target = self
            button.action = #selector(activateToggle)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        for name in ["Left 1", "Left 2"] {
            let item = makeItem(name: name, length: NSStatusItem.variableLength)
            item.button?.title = name
            item.button?.setAccessibilityLabel("Single-item probe \(name)")
        }
        updateGlyph()
        log("Ready. Arrange only probe items as Left 2, Left 1, arrow if needed. Right-click arrow to quit.")
    }

    private func makeItem(name: String, length: CGFloat) -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: length)
        let identifier = "Ice.SingleItemProbe.\(runID).\(name)"
        item.autosaveName = identifier
        item.button?.setAccessibilityIdentifier(identifier)
        items.append(item)
        return item
    }

    @objc private func activateToggle() {
        guard let button = toggleItem?.button else { return }
        let event = NSApp.currentEvent
        let freshOwnMouseEvent: Bool
        if let event,
           event.windowNumber == button.window?.windowNumber,
           [.leftMouseDown, .leftMouseUp, .rightMouseUp].contains(event.type) {
            let age = ProcessInfo.processInfo.systemUptime - event.timestamp
            freshOwnMouseEvent = age >= 0 && age < 0.5
        } else {
            freshOwnMouseEvent = false
        }

        if freshOwnMouseEvent, let event {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard !flags.contains(.command) else {
                log("Ignored Command action: native reordering owns the gesture.")
                return
            }
            let point = button.convert(event.locationInWindow, from: nil)
            let iconRect = CGRect(
                x: max(button.bounds.minX, button.bounds.maxX - iconSlotWidth),
                y: button.bounds.minY,
                width: min(iconSlotWidth, button.bounds.width),
                height: button.bounds.height
            )
            guard iconRect.contains(point) else {
                log("Ignored mouse action outside right-hand icon slot.")
                return
            }
            if event.type == .rightMouseUp || flags.contains(.control) {
                showMenu(button: button)
                return
            }
        }
        toggle()
    }

    @objc private func toggle() {
        guard let item = toggleItem, let screen = item.button?.window?.screen ?? NSScreen.main else { return }
        isHidden.toggle()
        actionCount += 1
        // Match the existing experiment's bounded native overflow width. Do not
        // request a gigantic item, which macOS 27 may discard altogether.
        let leftEdge = screen.auxiliaryTopRightArea?.minX ?? (screen.frame.minX + 300)
        let rightEdge = item.button?.window?.frame.maxX ?? screen.frame.maxX
        let nativePadding = max(0, (item.button?.window?.frame.width ?? item.length) - item.length)
        let availableWidth = rightEdge - leftEdge - nativePadding - iconSlotWidth
        log("Before resize: window=\(String(describing: item.button?.window?.frame)), available=\(availableWidth)")
        item.length = isHidden ? max(iconSlotWidth, availableWidth) : iconSlotWidth
        updateGlyph()
        log("Action \(actionCount): \(isHidden ? "hidden" : "shown"), requested width=\(item.length)")
        // A diagnostic read in the next event turn; never defers the actual toggle.
        DispatchQueue.main.async { [weak self] in
            self?.logGeometry()
        }
    }

    private func updateGlyph() {
        guard let item = toggleItem, let button = item.button else { return }
        guard let glyph = NSImage(
            systemSymbolName: isHidden ? "chevron.left" : "chevron.right",
            accessibilityDescription: isHidden ? "Show probe items" : "Hide probe items"
        ) else { return }
        // Experiment B: the hosted status button may ignore cell alignment.
        // Keep its ordinary centered image, but put the glyph at the right of
        // a transparent template canvas instead of relying on imagePosition.
        let imageSize = NSSize(width: max(16, item.length - 16), height: 18)
        let image = NSImage(size: imageSize, flipped: false) { rect in
            let glyphSize = NSSize(width: min(10, glyph.size.width), height: 14)
            glyph.draw(in: NSRect(x: rect.maxX - glyphSize.width - 1,
                                 y: (rect.height - glyphSize.height) / 2,
                                 width: glyphSize.width, height: glyphSize.height))
            return true
        }
        image.isTemplate = true
        button.image = image
        button.toolTip = "Single-item probe — \(isHidden ? "show" : "hide") test items; right-click to quit"
    }

    private func showMenu(button: NSStatusBarButton) {
        let menu = NSMenu()
        let toggle = NSMenuItem(
            title: isHidden ? "Show Probe Items" : "Hide Probe Items",
            action: #selector(self.toggle), keyEquivalent: ""
        )
        toggle.target = self
        menu.addItem(toggle)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Probe", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
        menu.popUp(positioning: nil, at: NSPoint(x: button.bounds.maxX - iconSlotWidth, y: button.bounds.minY), in: button)
    }

    private func logGeometry() {
        guard let button = toggleItem?.button else { return }
        let imageRect = button.cell?.imageRect(forBounds: button.bounds) ?? .zero
        log("Native frame=\(String(describing: button.window?.frame)); button=\(button.bounds); glyph=\(imageRect)")
    }

    private func log(_ message: String) {
        print(String(format: "%.3f", ProcessInfo.processInfo.systemUptime), message)
        fflush(stdout)
        NSLog("Probe: %@", message)
    }

    func applicationWillTerminate(_ notification: Notification) {
        for item in items { NSStatusBar.system.removeStatusItem(item) }
        items.removeAll()
        toggleItem = nil
    }
}

@main
enum NativeSingleItemToggleProbeMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = NativeSingleItemToggleProbe()
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
