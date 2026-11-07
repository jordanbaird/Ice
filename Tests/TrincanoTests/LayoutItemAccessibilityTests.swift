//
//  LayoutItemAccessibilityTests.swift
//  TrincanoTests
//

import AppKit
import Testing

/// A real `NSView` is configured with the same function `LayoutBarItemView`
/// calls. The layout items can only be rearranged by dragging, so VoiceOver
/// must not announce them as pressable buttons.
@MainActor
struct LayoutItemAccessibilityTests {
    private func make(movable: Bool) -> NSView {
        let view = NSView(frame: .zero)
        view.applyLayoutItemAccessibility(name: "Wi-Fi", isMovable: movable)
        return view
    }

    @Test func itemIsAnAccessibilityElementWithItsName() {
        let view = make(movable: true)
        #expect(view.isAccessibilityElement())
        #expect(view.accessibilityLabel()?.hasPrefix("Wi-Fi") == true)
    }

    @Test func itemIsNotAnnouncedAsAPressableButton() {
        let view = make(movable: true)
        #expect(view.accessibilityRole() != .button)
    }

    @Test func itemDoesNotPromiseAnActionItCannotPerform() {
        // No press action is implemented, so the help must not tell the user to drag
        // as if VoiceOver could do it, and the actions list must be empty.
        let view = make(movable: true)
        #expect(view.accessibilityActionNames().isEmpty)
        #expect(view.accessibilityHelp() == nil)
    }

    @Test func unmovableItemSaysSo() {
        let view = make(movable: false)
        #expect(view.accessibilityLabel()?.contains("Wi-Fi") == true)
        #expect(view.accessibilityLabel() != make(movable: true).accessibilityLabel())
    }
}
