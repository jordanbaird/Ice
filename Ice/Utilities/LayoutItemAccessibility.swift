//
//  LayoutItemAccessibility.swift
//  Ice
//

import AppKit

extension NSView {
    /// Configures VoiceOver for an item in the menu bar layout editor.
    ///
    /// The items are rearranged only by dragging, and the view implements no
    /// press action, so it is announced as an image (read, not pressable) with
    /// no help text promising an action VoiceOver can't perform. VoiceOver move
    /// actions are future work (see docs/pendencias.md).
    func applyLayoutItemAccessibility(name: String, isMovable: Bool) {
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel(isMovable ? name : String(localized: "\(name), not movable"))
        setAccessibilityHelp(nil)
    }
}
