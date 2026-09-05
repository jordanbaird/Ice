//
//  MacOS27NativeMenuBarHiding.swift
//  Ice
//

import Cocoa

/// Hides a contiguous section by resizing an Ice-owned blank status item.
/// macOS lays out and handles every other item, including overflow and clicks.
@MainActor
final class MacOS27NativeMenuBarHiding {
    private struct Spacer {
        let item: NSStatusItem
    }

    private var spacers = [MenuBarSection.Name: Spacer]()

    isolated deinit {
        removeAll()
    }

    func isConcealing(_ section: MenuBarSection.Name) -> Bool {
        guard let spacer = spacers[section] else { return false }
        return spacer.item.isVisible && spacer.item.length > 1
    }

    func prepare(section: MenuBarSection.Name, anchorPosition: CGFloat) {
        guard spacers[section] == nil else { return }
        let name = "Ice.NativeBoundary.\(section.rawValue).v2"
        // Equal preferred positions have unstable ordering after a relaunch.
        // The spacer must sort strictly to the left of the visible Ice item.
        let key = "NSStatusItem Preferred Position \(name)"
        if UserDefaults.standard.object(forKey: key) == nil {
            UserDefaults.standard.set(anchorPosition + 1, forKey: key)
        }
        let item = NSStatusBar.system.statusItem(withLength: 1)
        item.autosaveName = name
        item.button?.title = ""
        item.button?.image = nil
        item.button?.isEnabled = false
        item.button?.setAccessibilityIdentifier(name)
        spacers[section] = Spacer(item: item)
        withdraw(item)
    }

    /// AppKit reserves a real slot even for a one-point item. Publish the
    /// narrow boundary only while an explicit operation needs a drag handle.
    func prepareForHiding(anchorPosition: CGFloat) {
        prepare(section: .hidden, anchorPosition: anchorPosition)
        if let spacer = spacers[.hidden] { showNarrow(spacer.item) }
    }

    func showForLayout(anchorPosition: CGFloat, alwaysHiddenAnchor: CGFloat?) {
        prepare(section: .hidden, anchorPosition: anchorPosition)
        if let alwaysHiddenAnchor {
            prepare(section: .alwaysHidden, anchorPosition: alwaysHiddenAnchor)
        }
        for (section, spacer) in spacers {
            if section == .hidden || alwaysHiddenAnchor != nil {
                showNarrow(spacer.item)
            } else {
                withdraw(spacer.item)
            }
        }
    }

    private func showNarrow(_ item: NSStatusItem) {
        if item.length != 1 { item.length = 1 }
        if item.button?.isEnabled == false { item.button?.isEnabled = true }
        if !item.isVisible { item.isVisible = true }
    }

    private func withdraw(_ item: NSStatusItem) {
        guard item.isVisible else { return }
        // Hiding an NSStatusItem clears its saved position. Preserve only our
        // own position; the pre-hide check reconciles native user reordering.
        let key = "NSStatusItem Preferred Position \(item.autosaveName ?? "")"
        let position = UserDefaults.standard.object(forKey: key)
        item.isVisible = false
        if let position { UserDefaults.standard.set(position, forKey: key) }
        if item.button?.isEnabled == true { item.button?.isEnabled = false }
    }

    @available(macOS 27.0, *)
    func setHidden(
        _ hidden: Bool,
        section: MenuBarSection.Name,
        anchorPosition: CGFloat,
        screen: NSScreen
    ) {
        guard hidden else {
            guard let spacer = spacers[section] else { return }
            withdraw(spacer.item)
            return
        }

        // An item wider than the entire native status region is discarded on
        // macOS 27. A width within that region makes its left neighbors overflow.
        let regionWidth = screen.auxiliaryTopRightArea?.width
            ?? (screen.frame.width - (screen.getApplicationMenuFrame()?.width ?? 300))
        let length = max(32, regionWidth - 32)

        prepare(section: section, anchorPosition: anchorPosition)
        guard let spacer = spacers[section] else { return }

        if spacer.item.button?.isEnabled == true { spacer.item.button?.isEnabled = false }
        if spacer.item.length != length { spacer.item.length = length }
        if !spacer.item.isVisible { spacer.item.isVisible = true }
    }

    func removeAll() {
        for spacer in spacers.values {
            spacer.item.isVisible = false
            NSStatusBar.system.removeStatusItem(spacer.item)
        }
        spacers.removeAll()
    }
}
