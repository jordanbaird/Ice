//
//  CodeSigning.swift
//  Shared
//

import Security
import XPC

enum CodeSigningInfo {
    /// The team identifier of the current process, or `nil` if the
    /// process is ad hoc signed or signed with a local certificate.
    static var teamIdentifier: String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else {
            return nil
        }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else {
            return nil
        }
        var info: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(staticCode, flags, &info) == errSecSuccess else {
            return nil
        }
        return (info as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String
    }
}

@available(macOS 26.0, *)
extension XPCPeerRequirement {
    /// Returns the requirement for a peer whose signing identifier is
    /// `signingIdentifier`, chosen by ``XPCPeerPolicy``.
    static func trincanoPeer(signingIdentifier: String) -> XPCPeerRequirement {
        switch XPCPeerPolicy.make(
            teamIdentifier: CodeSigningInfo.teamIdentifier,
            peerSigningIdentifier: signingIdentifier
        ) {
        case .sameTeam(let identifier):
            return .isFromSameTeam(andMatchesSigningIdentifier: identifier)
        case .signingIdentifier(let identifier):
            var requirements = XPCDictionary()
            requirements["signing-identifier"] = identifier
            return XPCPeerRequirement(lightweightCodeRequirements: requirements)
        }
    }
}
