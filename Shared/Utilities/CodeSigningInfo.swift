//
//  CodeSigningInfo.swift
//  Shared
//

import Security

/// Code signing details for the current process.
enum CodeSigningInfo {
    /// The team identifier the current process is signed with, if any.
    ///
    /// Ad-hoc signed builds (for example, local builds without a developer
    /// account) have no team identifier.
    static let teamIdentifier: String? = {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else {
            return nil
        }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else {
            return nil
        }
        var info: CFDictionary?
        guard
            SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
            let info = info as? [String: Any]
        else {
            return nil
        }
        return info[kSecCodeInfoTeamIdentifier as String] as? String
    }()

    /// A Boolean value that indicates whether XPC peers can be required
    /// to be signed with the same team identifier as the current process.
    ///
    /// The same-team requirement always fails for ad-hoc signed builds.
    static var canRequireSameTeam: Bool {
        teamIdentifier != nil
    }
}
