//
//  Predicates.swift
//  Ice
//

import CoreGraphics

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
}

// MARK: Window Predicates
extension Predicates where Input == WindowInfo {
    /// Creates a predicate that returns whether a window is the wallpaper window
    /// for the given display.
    static func wallpaperWindow(for display: DisplayInfo) -> NonThrowingPredicate {
        predicate { window in
            // wallpaper window belongs to the Dock process
            window.owningApplication?.bundleIdentifier == "com.apple.dock" &&
            window.title?.hasPrefix("Wallpaper") == true &&
            display.bounds.contains(window.frame)
        }
    }

    /// Creates a predicate that returns whether a window is the menu bar window for
    /// the given display.
    static func menuBarWindow(for display: DisplayInfo) -> NonThrowingPredicate {
        predicate { window in
            // menu bar window belongs to the WindowServer process (owningApplication should be nil)
            window.owningApplication == nil &&
            window.isOnScreen &&
            window.windowLayer == kCGMainMenuWindowLevel &&
            window.title == "Menubar" &&
            display.bounds.contains(window.frame)
        }
    }

    /// Creates a predicate that returns whether a window is the fullscreen backdrop
    /// window for the given display.
    static func fullscreenBackdropWindow(for display: DisplayInfo) -> NonThrowingPredicate {
        predicate { window in
            // fullscreen backdrop window belongs to the Dock process
            window.owningApplication?.bundleIdentifier == "com.apple.dock" &&
            window.title == "Fullscreen Backdrop" &&
            window.frame == display.bounds
        }
    }
}
