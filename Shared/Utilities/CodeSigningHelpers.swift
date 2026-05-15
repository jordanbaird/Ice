//
//  CodeSigningHelpers.swift
//  Shared
//

import Foundation
import Security

/// Returns the team identifier of the currently running process,
/// or `nil` if the process is ad-hoc signed (or unsigned).
///
/// Used to gate XPC peer-requirement checks: `.isFromSameTeam()`
/// silently rejects every connection when both peers are ad-hoc
/// signed (no team identifier to compare), so callers must skip
/// the requirement entirely on ad-hoc builds.
func currentProcessTeamID() -> String? {
    var code: SecCode?
    guard SecCodeCopySelf([], &code) == errSecSuccess, let code else {
        return nil
    }
    var info: CFDictionary?
    let status = SecCodeCopySigningInformation(
        code as! SecStaticCode,
        SecCSFlags(rawValue: kSecCSSigningInformation),
        &info
    )
    guard status == errSecSuccess,
          let dict = info as? [String: Any],
          let teamID = dict[kSecCodeInfoTeamIdentifier as String] as? String,
          !teamID.isEmpty
    else {
        return nil
    }
    return teamID
}
