//
//  ControlItemIconMigrationTests.swift
//  TrincanoTests
//

import Foundation
import Testing

/// Stored icon preferences are decoded and then migrated: only the legacy Ice
/// cube becomes the Frost Bar; every other choice is kept as it was.
struct ControlItemIconMigrationTests {
    /// Encodes like the app does when it saves the preference.
    private func stored(_ set: ControlItemImageSet) throws -> Data {
        try JSONEncoder().encode(set)
    }

    private func load(_ data: Data) throws -> ControlItemImageSet {
        try JSONDecoder().decode(ControlItemImageSet.self, from: data).migratedFromLegacy()
    }

    private let legacyCube = ControlItemImageSet(
        name: .iceCube, hidden: .catalog("IceCubeStroke"), visible: .catalog("IceCubeFill")
    )

    @Test func legacyIceCubeBecomesTheFrostBar() throws {
        let migrated = try load(stored(legacyCube))
        #expect(migrated == ControlItemImageSet.defaultIceIcon)
        #expect(migrated.name == .frostBar)
        #expect(migrated.hidden == .catalog("FrostBarFill"))
        #expect(migrated.visible == .catalog("FrostBarStroke"))
    }

    @Test func migratedValueSurvivesAReencodeAndReload() throws {
        let once = try load(stored(legacyCube))
        let twice = try load(stored(once))
        #expect(twice == once)
        #expect(twice.name == .frostBar)
    }

    @Test func dotIsPreserved() throws {
        let dot = ControlItemImageSet(name: .dot, hidden: .catalog("DotFill"), visible: .catalog("DotStroke"))
        #expect(try load(stored(dot)) == dot)
    }

    @Test func symbolAndEllipsisChoicesArePreserved() throws {
        let arrow = ControlItemImageSet(
            name: .arrow, hidden: .symbol("arrowshape.left.fill"), visible: .symbol("arrowshape.right.fill")
        )
        let ellipsis = ControlItemImageSet(
            name: .ellipsis, hidden: .catalog("EllipsisFill"), visible: .catalog("EllipsisStroke")
        )
        #expect(try load(stored(arrow)) == arrow)
        #expect(try load(stored(ellipsis)) == ellipsis)
    }

    @Test func customImageIsPreserved() throws {
        let custom = ControlItemImageSet(name: .custom, image: .data(Data([0x89, 0x50, 0x4E, 0x47])))
        let loaded = try load(stored(custom))
        #expect(loaded == custom)
        #expect(loaded.name == .custom)
    }

    @Test func frostBarChoiceIsPreserved() throws {
        let frost = ControlItemImageSet.defaultIceIcon
        #expect(try load(stored(frost)) == frost)
    }

    @Test func userCanNoLongerPickTheLegacyCube() {
        #expect(!ControlItemImageSet.userSelectableIceIcons.contains { $0.name == .iceCube })
        #expect(ControlItemImageSet.userSelectableIceIcons.first?.name == .frostBar)
    }
}
