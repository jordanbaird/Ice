//
//  XPCPeerPolicy.swift
//  Shared
//

/// Decides which requirement an XPC endpoint places on its peer.
///
/// The decision is pure (no Security or XPC calls) so it can be tested.
/// Builds signed with a Developer ID or Apple Development certificate
/// carry a team identifier and keep the same-team requirement. Builds
/// signed with a local certificate (or ad hoc) have no team identifier,
/// so the same-team check can never pass; those fall back to requiring
/// the peer's exact signing identifier. The requirement is never dropped.
enum XPCPeerPolicy: Equatable {
    /// The peer must have the same team identifier and signing identifier.
    case sameTeam(signingIdentifier: String)

    /// The peer must have exactly this signing identifier.
    case signingIdentifier(String)

    /// Returns the policy for a process with the given team identifier.
    ///
    /// - Parameters:
    ///   - teamIdentifier: The team identifier of the current process,
    ///     or `nil` if it has none.
    ///   - peerSigningIdentifier: The signing identifier the peer must have.
    static func make(teamIdentifier: String?, peerSigningIdentifier: String) -> XPCPeerPolicy {
        if let teamIdentifier, !teamIdentifier.isEmpty {
            .sameTeam(signingIdentifier: peerSigningIdentifier)
        } else {
            .signingIdentifier(peerSigningIdentifier)
        }
    }
}
