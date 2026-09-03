//
//  CodeSigning.swift
//  Shared
//

import Foundation
import Security

/// Information about the code signature of the current process.
enum CodeSigning {
    /// A Boolean value that indicates whether the current process is signed
    /// with a team identifier.
    ///
    /// Ad hoc and self-signed builds have no team identifier, so XPC peer
    /// requirements based on the team must not be applied to them, or the
    /// app and its XPC services would refuse to talk to each other.
    static let hasTeamIdentifier: Bool = {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else {
            return false
        }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code as! SecStaticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess else { // swiftlint:disable:this force_cast
            return false
        }
        let dict = info as? [String: Any] ?? [:]
        guard let team = dict[kSecCodeInfoTeamIdentifier as String] as? String else {
            return false
        }
        return !team.isEmpty
    }()
}
