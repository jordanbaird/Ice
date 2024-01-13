//
//  NSApplication+windowWithIdentifier.swift
//  Ice
//

import Cocoa

extension NSApplication {
    /// Returns the window with the given identifier.
    func window(withIdentifier identifier: String) -> NSWindow? {
        windows.first { $0.identifier?.rawValue == identifier }
    }
}
