//
//  XPCPeerPolicyTests.swift
//  TrincanoTests
//

import Testing

struct XPCPeerPolicyTests {
    private let peer = "br.com.pilutech.trincano"

    @Test func teamIdentifierKeepsSameTeamRequirement() {
        let policy = XPCPeerPolicy.make(teamIdentifier: "ABCDE12345", peerSigningIdentifier: peer)
        #expect(policy == .sameTeam(signingIdentifier: peer))
    }

    @Test func missingTeamIdentifierFallsBackToSigningIdentifier() {
        let policy = XPCPeerPolicy.make(teamIdentifier: nil, peerSigningIdentifier: peer)
        #expect(policy == .signingIdentifier(peer))
    }

    @Test func emptyTeamIdentifierIsTreatedAsMissing() {
        let policy = XPCPeerPolicy.make(teamIdentifier: "", peerSigningIdentifier: peer)
        #expect(policy == .signingIdentifier(peer))
    }

    @Test func requirementIsNeverDropped() {
        for team in [nil, "", "ABCDE12345"] as [String?] {
            let policy = XPCPeerPolicy.make(teamIdentifier: team, peerSigningIdentifier: peer)
            switch policy {
            case .sameTeam(let id), .signingIdentifier(let id):
                #expect(id == peer)
            }
        }
    }
}
