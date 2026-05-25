//
//  MenuBarItemService.swift
//  Shared
//

import Foundation
import Security

enum MenuBarItemService {
    static let name = "com.jordanbaird.Ice.MenuBarItemService"

    /// Returns the Team Identifier of the currently running process, or
    /// `nil` if the binary is unsigned, ad-hoc signed, or the team
    /// identifier cannot be read.
    ///
    /// Both sides of the XPC connection (Ice ↔ MenuBarItemService.xpc) use
    /// this to decide whether to enforce `.isFromSameTeam()` on their
    /// peer requirements. The `.isFromSameTeam()` predicate silently
    /// rejects every peer when there's no team identifier to compare —
    /// the case for any ad-hoc-signed build, including every community
    /// fork shipped without an Apple Developer Program account. Without
    /// the guard, Ice rejects its own helper service, the helper
    /// rejects Ice back, and the Menu Bar Layout settings pane spins
    /// forever on "Loading menu bar items…". This is the same class as
    /// upstream issues #744 and #891.
    static func ownTeamIdentifier() -> String? {
        var staticCode: SecStaticCode?
        guard
            SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &staticCode) == errSecSuccess,
            let code = staticCode
        else {
            return nil
        }
        var info: CFDictionary?
        guard
            SecCodeCopySigningInformation(code, SecCSFlags(rawValue: 0), &info) == errSecSuccess,
            let dict = info as? [String: Any],
            let teamID = dict[kSecCodeInfoTeamIdentifier as String] as? String,
            !teamID.isEmpty
        else {
            return nil
        }
        return teamID
    }
}

extension MenuBarItemService {
    enum Request: Codable {
        case start
        case sourcePID(WindowInfo)
    }

    enum Response: Codable {
        case start
        case sourcePID(pid_t?)
    }
}
