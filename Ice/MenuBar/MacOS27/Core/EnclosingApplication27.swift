//
//  EnclosingApplication27.swift
//  Ice
//

import Foundation

/// Finding the application a menu bar item's process belongs to.
///
/// An item's owner is not always the application the user installed. Docker Desktop's item comes
/// from `com.electron.dockerdesktop`, a helper that lives inside `Docker.app` and calls itself
/// something else, while macOS's own per-application menu bar switch is kept for `Docker.app`
/// itself, `com.docker.docker`. Ice looked for the helper's identifier among those switches, found
/// nothing, and left the item on the bar (measured 2026-10-26).
enum EnclosingApplication27 {
    /// The outermost application bundle on the given bundle's path, or `nil` when the bundle is
    /// the outermost one already.
    ///
    /// `/Applications/Docker.app/Contents/MacOS/Docker Desktop.app` gives `/Applications/Docker.app`;
    /// `/Applications/Cursor.app` gives nothing, being its own.
    static func outermostApplicationPath(of bundlePath: String) -> String? {
        let parts = bundlePath.split(separator: "/", omittingEmptySubsequences: false)
        guard let first = parts.firstIndex(where: { $0.hasSuffix(".app") }) else {
            return nil
        }
        let outermost = "/" + parts[1...first].joined(separator: "/")
        return outermost == bundlePath ? nil : outermost
    }
}
