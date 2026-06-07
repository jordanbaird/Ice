//
//  CodeSigning.swift
//  Shared
//

import Security

/// Utilities for inspecting the current process's code signature.
enum CodeSigning {
    /// The Team Identifier of the running process, or `nil` if the process
    /// is unsigned or ad-hoc signed (i.e. has no Team Identifier).
    ///
    /// Ad-hoc/local development builds have no Team Identifier, which is why
    /// this is used to decide whether the `isFromSameTeam` XPC peer
    /// requirement can be satisfied.
    static var teamIdentifier: String? {
        var code: SecCode?
        guard
            SecCodeCopySelf([], &code) == errSecSuccess,
            let code
        else {
            return nil
        }

        var staticCode: SecStaticCode?
        guard
            SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess,
            let staticCode
        else {
            return nil
        }

        var info: CFDictionary?
        guard
            SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
            let dict = info as? [String: Any],
            let team = dict[kSecCodeInfoTeamIdentifier as String] as? String,
            !team.isEmpty
        else {
            return nil
        }

        return team
    }

    /// A Boolean value indicating whether the current process has a Team
    /// Identifier, meaning the `isFromSameTeam` XPC peer requirement can be
    /// enforced. Ad-hoc/local builds return `false`.
    static var hasTeamIdentifier: Bool {
        teamIdentifier != nil
    }
}
