//
//  MacOS27NativeMenuBarHiding.swift
//  Ice
//

import Cocoa
import OSLog

/// Hides a contiguous section by resizing an Ice-owned blank status item.
/// macOS lays out and handles every other item, including overflow and clicks.
@MainActor
final class MacOS27NativeMenuBarHiding {
    private struct Spacer {
        let item: NSStatusItem
    }

    private let logger = Logger(category: "MacOS27NativeMenuBarHiding")

    private var spacers = [MenuBarSection.Name: Spacer]()

    isolated deinit {
        removeAll()
    }

    /// A short description of a section's spacer, for logging.
    func debugDescription(for section: MenuBarSection.Name) -> String {
        guard let spacer = spacers[section] else { return "no spacer" }
        return "spacer visible=\(spacer.item.isVisible) length=\(spacer.item.length)"
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
        logger.notice("Withdrawing \(item.autosaveName ?? "spacer", privacy: .public) (length \(item.length))")
        // Hiding an NSStatusItem clears its saved position. Preserve only our
        // own position; the pre-hide check reconciles native user reordering.
        let key = "NSStatusItem Preferred Position \(item.autosaveName ?? "")"
        let position = UserDefaults.standard.object(forKey: key)
        item.isVisible = false
        if let position { UserDefaults.standard.set(position, forKey: key) }
        if item.button?.isEnabled == true { item.button?.isEnabled = false }
    }

    /// Sets whether a section's spacer conceals the items to its left.
    ///
    /// - Parameter controlFrame: The current frame of the item immediately to
    ///   the right of the spacer, in global display coordinates. When known,
    ///   the spacer is sized to the space actually available to its left.
    @available(macOS 27.0, *)
    func setHidden(
        _ hidden: Bool,
        section: MenuBarSection.Name,
        anchorPosition: CGFloat,
        screen: NSScreen,
        controlFrame: CGRect? = nil
    ) {
        guard hidden else {
            guard let spacer = spacers[section] else { return }
            withdraw(spacer.item)
            return
        }

        prepare(section: section, anchorPosition: anchorPosition)
        guard let spacer = spacers[section] else { return }

        let length: CGFloat
        if let controlFrame {
            length = Self.concealingLength(
                controlMinX: controlFrame.minX,
                screen: screen,
                applicationMenuMaxX: screen.getApplicationMenuFrame()?.maxX
            )
        } else if spacer.item.isVisible, spacer.item.length > 1 {
            // Without a fresh frame, keep the length that is already concealing.
            length = spacer.item.length
        } else {
            // An item wider than the entire native status region is discarded on
            // macOS 27. A width within that region makes its left neighbors overflow.
            let regionWidth = screen.auxiliaryTopRightArea?.width
                ?? (screen.frame.width - (screen.getApplicationMenuFrame()?.width ?? 300))
            length = max(32, regionWidth - 32)
        }

        if spacer.item.button?.isEnabled == true { spacer.item.button?.isEnabled = false }
        if spacer.item.length != length {
            logger.notice("Sizing \(section.rawValue, privacy: .public) spacer to \(length) (control frame: \(controlFrame?.debugDescription ?? "unknown", privacy: .public))")
            spacer.item.length = length
        }
        if !spacer.item.isVisible { spacer.item.isVisible = true }
    }

    /// The current length of a section's spacer, if it has one.
    func spacerLength(for section: MenuBarSection.Name) -> CGFloat? {
        spacers[section]?.item.length
    }

    /// Sets a section's spacer to an explicit length.
    ///
    /// The photo pass uses this to give back the menu bar space a few items at
    /// a time, so macOS draws them long enough to be photographed.
    @available(macOS 27.0, *)
    func setConcealingLength(_ length: CGFloat, section: MenuBarSection.Name, anchorPosition: CGFloat) {
        prepare(section: section, anchorPosition: anchorPosition)
        guard let spacer = spacers[section] else { return }
        let clamped = max(1, length)
        if spacer.item.length != clamped {
            spacer.item.length = clamped
        }
        if !spacer.item.isVisible {
            spacer.item.isVisible = true
        }
    }

    /// Returns a spacer length that fills the space available to the left of
    /// the item at `controlMinX`, so every item to the spacer's left overflows.
    ///
    /// On macOS 27, a status item that doesn't fit is discarded, and items
    /// that don't fit right of the notch move to its left. A spacer beside an
    /// item right of the notch must therefore be wider than the remaining gap
    /// there, so that it moves left of the notch and fills that side instead.
    static func concealingLength(
        controlMinX: CGFloat,
        screen: NSScreen,
        applicationMenuMaxX: CGFloat?
    ) -> CGFloat {
        // Leave room for the native overflow indicator.
        let margin: CGFloat = 32
        let minimumLength: CGFloat = 32
        let menusMaxX = max(screen.frame.minX, applicationMenuMaxX ?? screen.frame.minX)

        guard
            let leftArea = screen.auxiliaryTopLeftArea,
            let rightArea = screen.auxiliaryTopRightArea
        else {
            return max(minimumLength, controlMinX - menusMaxX - margin)
        }

        let notchMinX = leftArea.maxX
        let notchMaxX = rightArea.minX
        guard controlMinX >= notchMaxX else {
            return max(minimumLength, min(controlMinX, notchMinX) - menusMaxX - margin)
        }

        let rightGap = controlMinX - notchMaxX
        let leftSegment = notchMinX - menusMaxX - margin
        if leftSegment > rightGap {
            return leftSegment
        }
        // The left side is too small to hold a spacer wider than the right
        // gap. Fill the right gap; items can still show left of the notch.
        return max(minimumLength, rightGap - margin)
    }

    func removeAll() {
        for spacer in spacers.values {
            spacer.item.isVisible = false
            NSStatusBar.system.removeStatusItem(spacer.item)
        }
        spacers.removeAll()
    }
}
