//
//  Predicates.swift
//  Ice
//

import Cocoa

/// A namespace for predicates.
enum Predicates<Input> {
    /// A throwing predicate that takes an input and returns a Boolean value.
    typealias ThrowingPredicate = (Input) throws -> Bool

    /// A predicate that takes an input and returns a Boolean value.
    typealias NonThrowingPredicate = (Input) -> Bool

    /// Creates a throwing predicate that takes an input and returns a Boolean value.
    static func predicate(_ body: @escaping (Input) throws -> Bool) -> ThrowingPredicate {
        return body
    }

    /// Creates a predicate takes an input and returns a Boolean value.
    static func predicate(_ body: @escaping (Input) -> Bool) -> NonThrowingPredicate {
        return body
    }

    /// Creates a throwing predicate that doesn't take an input and returns a Boolean value.
    static func predicate(_ body: @escaping () throws -> Bool) -> ThrowingPredicate {
        predicate { _ in try body() }
    }

    /// Creates a predicate that doesn't take an input and returns a Boolean value.
    static func predicate(_ body: @escaping () -> Bool) -> NonThrowingPredicate {
        predicate { _ in body() }
    }
}

// MARK: - Window Predicates

extension Predicates where Input == WindowInfo {
    /// Creates a predicate that returns whether a window is the wallpaper window
    /// for the given display.
    static func wallpaperWindow(for display: CGDirectDisplayID) -> NonThrowingPredicate {
        predicate { window in
            // wallpaper window belongs to the Dock process
            window.owningApplication?.bundleIdentifier == "com.apple.dock" &&
            window.title?.hasPrefix("Wallpaper") == true &&
            CGDisplayBounds(display).contains(window.frame)
        }
    }

    /// Creates a predicate that returns whether a window is the menu bar window for
    /// the given display.
    static func menuBarWindow(for display: CGDirectDisplayID) -> NonThrowingPredicate {
        predicate { window in
            // menu bar window belongs to the WindowServer process
            window.isWindowServerWindow &&
            window.isOnScreen &&
            window.layer == kCGMainMenuWindowLevel &&
            window.title == "Menubar" &&
            CGDisplayBounds(display).contains(window.frame)
        }
    }
}

// MARK: - Menu Bar Item Predicates

extension Predicates where Input == MenuBarItem {
    /// A group of predicates that separates menu bar items into sections.
    typealias SectionPredicates = (
        isInVisibleSection: NonThrowingPredicate,
        isInHiddenSection: NonThrowingPredicate,
        isInAlwaysHiddenSection: NonThrowingPredicate
    )

    /// Creates a predicate that returns whether a menu bar item is in the visible section
    /// using the control item for the hidden section as a delimiter.
    static func isInVisibleSection(hiddenControlItem: MenuBarItem) -> NonThrowingPredicate {
        predicate { item in
            item.frame.minX >= hiddenControlItem.frame.maxX
        }
    }

    /// Creates a predicate that returns whether a menu bar item is in the hidden section
    /// using the control items for the hidden and always hidden sections as delimiters.
    static func isInHiddenSection(hiddenControlItem: MenuBarItem, alwaysHiddenControlItem: MenuBarItem?) -> NonThrowingPredicate {
        if let alwaysHiddenControlItem {
            predicate { item in
                item.frame.maxX <= hiddenControlItem.frame.minX &&
                item.frame.minX >= alwaysHiddenControlItem.frame.maxX
            }
        } else {
            predicate { item in
                item.frame.maxX <= hiddenControlItem.frame.minX
            }
        }
    }

    /// Creates a predicate that returns whether a menu bar item is in the always-hidden
    /// section using the control item for the always hidden section as a delimiter.
    static func isInAlwaysHiddenSection(alwaysHiddenControlItem: MenuBarItem?) -> NonThrowingPredicate {
        if let alwaysHiddenControlItem {
            predicate { item in
                item.frame.maxX <= alwaysHiddenControlItem.frame.minX
            }
        } else {
            predicate { false }
        }
    }

    /// Creates a group of predicates that separates menu bar items into sections.
    static func sectionPredicates(hiddenControlItem: MenuBarItem, alwaysHiddenControlItem: MenuBarItem?) -> SectionPredicates {
        SectionPredicates(
            isInVisibleSection: isInVisibleSection(hiddenControlItem: hiddenControlItem),
            isInHiddenSection: isInHiddenSection(hiddenControlItem: hiddenControlItem, alwaysHiddenControlItem: alwaysHiddenControlItem),
            isInAlwaysHiddenSection: isInAlwaysHiddenSection(alwaysHiddenControlItem: alwaysHiddenControlItem)
        )
    }
}

// MARK: - Control Item Predicates

extension Predicates where Input == NSLayoutConstraint {
    static func controlItemConstraint(button: NSStatusBarButton) -> NonThrowingPredicate {
        predicate { constraint in
            constraint.secondItem === button.superview
        }
    }
}
