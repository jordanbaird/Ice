//
//  CodeSigningInfo.swift
//  Shared
//

import Foundation
import OSLog
import Security

/// Information about the current process's code signature.
enum CodeSigningInfo {
    /// The result of inspecting the current process's code signature.
    enum SignatureState: Equatable {
        /// The signature has a team identifier, so same-team XPC peer
        /// requirements can be enforced.
        case team(String)
        /// The signature was read successfully but has no team
        /// identifier (e.g. an ad-hoc signed local build). Same-team
        /// peer requirements can never be satisfied, so callers may
        /// choose to skip them for this build.
        case noTeam
        /// The signature could not be read. Callers should treat this
        /// conservatively and keep verification enabled (fail closed),
        /// since a read failure is not proof of an ad-hoc signature.
        case unknown
    }

    /// The signature state of the current process.
    static let state: SignatureState = {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else {
            return .unknown
        }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else {
            return .unknown
        }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, [], &info) == errSecSuccess,
        let infoDict = info as? [String: Any] else {
            return .unknown
        }
        if
            let team = infoDict[kSecCodeInfoTeamIdentifier as String] as? String,
            !team.isEmpty
        {
            return .team(team)
        }
        return .noTeam
    }()

    /// Whether the current process's code signature has a team identifier.
    static var hasTeamIdentifier: Bool {
        if case .team = state {
            return true
        }
        return false
    }

    /// Whether same-team XPC peer requirements should be enforced for
    /// this build. Requirements are skipped only for builds that are
    /// verifiably signed without a team identifier; if the signature
    /// can't be read, verification stays on.
    static var shouldEnforceSameTeamRequirement: Bool {
        state != .noTeam
    }

    /// Logs the peer-verification decision for this build. Call once
    /// when setting up an XPC listener or connection.
    static func logPeerVerificationDecision() {
        switch state {
        case .team:
            break
        case .noTeam:
            Logger.default.warning(
                "Build is signed without a team identifier; accepting XPC connections without peer verification"
            )
        case .unknown:
            Logger.default.error(
                "Could not read code signature information; enforcing XPC peer verification"
            )
        }
    }
}
