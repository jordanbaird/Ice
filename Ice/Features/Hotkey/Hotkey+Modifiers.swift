//
//  Hotkey+Modifiers.swift
//  Ice
//

import Carbon.HIToolbox
import Cocoa

extension Hotkey {
    /// A bit mask containing the modifier keys for a hot key.
    struct Modifiers: OptionSet, Codable, Hashable {
        let rawValue: Int

        init(rawValue: Int) {
            self.rawValue = rawValue
        }

        /// The control `(⌃)` key.
        static let control   = Modifiers(rawValue: 1 << 0)
        /// The option `(⌥)` key.
        static let option    = Modifiers(rawValue: 1 << 1)
        /// The shift `(⇧)` key.
        static let shift     = Modifiers(rawValue: 1 << 2)
        /// The command `(⌘)` key.
        static let command   = Modifiers(rawValue: 1 << 3)

        /// All modifiers in the order displayed by the system, according
        /// to Apple's style guide.
        static let canonicalOrder: [Modifiers] = [.control, .option, .shift, .command]
    }
}

// MARK: Flag Conversions
extension Hotkey.Modifiers {

    // MARK: Conversion Properties

    /// The bit mask's string representation.
    var stringValue: String {
        var result = ""
        if contains(.control) {
            result.append("⌃")
        }
        if contains(.option) {
            result.append("⌥")
        }
        if contains(.shift) {
            result.append("⇧")
        }
        if contains(.command) {
            result.append("⌘")
        }
        return result
    }

    /// The bit mask's equivalent `NSEvent` modifier flags.
    var nsEventFlags: NSEvent.ModifierFlags {
        var result: NSEvent.ModifierFlags = []
        if contains(.control) {
            result.insert(.control)
        }
        if contains(.option) {
            result.insert(.option)
        }
        if contains(.shift) {
            result.insert(.shift)
        }
        if contains(.command) {
            result.insert(.command)
        }
        return result
    }

    /// The bit mask's equivalent `CoreGraphics` event flags.
    var cgEventFlags: CGEventFlags {
        var result: CGEventFlags = []
        if contains(.control) {
            result.insert(.maskControl)
        }
        if contains(.option) {
            result.insert(.maskAlternate)
        }
        if contains(.shift) {
            result.insert(.maskShift)
        }
        if contains(.command) {
            result.insert(.maskCommand)
        }
        return result
    }

    /// The bit mask's equivalent `Carbon` event flags.
    var carbonFlags: Int {
        var result = 0
        if contains(.control) {
            result |= controlKey
        }
        if contains(.option) {
            result |= optionKey
        }
        if contains(.shift) {
            result |= shiftKey
        }
        if contains(.command) {
            result |= cmdKey
        }
        return result
    }

    // MARK: Conversion Initializers

    /// Creates a bit mask with the given `NSEvent` modifier flags.
    init(nsEventFlags: NSEvent.ModifierFlags) {
        self.init()
        if nsEventFlags.contains(.control) {
            insert(.control)
        }
        if nsEventFlags.contains(.option) {
            insert(.option)
        }
        if nsEventFlags.contains(.shift) {
            insert(.shift)
        }
        if nsEventFlags.contains(.command) {
            insert(.command)
        }
    }

    /// Creates a bit mask with the given `CoreGraphics` event flags.
    init(cgEventFlags: CGEventFlags) {
        self.init()
        if cgEventFlags.contains(.maskControl) {
            insert(.control)
        }
        if cgEventFlags.contains(.maskAlternate) {
            insert(.option)
        }
        if cgEventFlags.contains(.maskShift) {
            insert(.shift)
        }
        if cgEventFlags.contains(.maskCommand) {
            insert(.command)
        }
    }

    /// Creates a bit mask with the given `Carbon` event flags.
    init(carbonFlags: Int) {
        self.init()
        if carbonFlags & controlKey == controlKey {
            insert(.control)
        }
        if carbonFlags & optionKey == optionKey {
            insert(.option)
        }
        if carbonFlags & shiftKey == shiftKey {
            insert(.shift)
        }
        if carbonFlags & cmdKey == cmdKey {
            insert(.command)
        }
    }
}
