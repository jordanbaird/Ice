//
//  DisplayProfilesTests.swift
//  TrincanoTests
//

import Foundation
import Testing

struct DisplayProfilesTests {
    private let builtIn = "AAAAAAAA-1111-1111-1111-AAAAAAAAAAAA"
    private let external = "BBBBBBBB-2222-2222-2222-BBBBBBBBBBBB"

    @Test func unknownDisplayFollowsTheGlobalSetting() {
        let profiles = DisplayProfiles()
        #expect(profiles.mode(for: builtIn) == .followGlobal)
        #expect(profiles.mode(for: nil) == .followGlobal)
    }

    @Test func eachDisplayKeepsItsOwnMode() {
        var profiles = DisplayProfiles()
        profiles.set(.bar, for: builtIn)
        profiles.set(.inline, for: external)
        #expect(profiles.mode(for: builtIn) == .bar)
        #expect(profiles.mode(for: external) == .inline)
    }

    @Test func settingFollowGlobalRemovesTheEntry() {
        var profiles = DisplayProfiles()
        profiles.set(.bar, for: builtIn)
        profiles.set(.followGlobal, for: builtIn)
        #expect(profiles == DisplayProfiles())
    }

    @Test func policyCombinesTheGlobalSettingAndTheProfile() {
        #expect(DisplayBarPolicy.useBar(global: false, mode: .followGlobal) == false)
        #expect(DisplayBarPolicy.useBar(global: true, mode: .followGlobal))
        #expect(DisplayBarPolicy.useBar(global: false, mode: .bar))
        #expect(DisplayBarPolicy.useBar(global: true, mode: .inline) == false)
    }

    @Test func roundTripsThroughData() throws {
        var profiles = DisplayProfiles()
        profiles.set(.bar, for: builtIn)
        profiles.set(.inline, for: external)
        #expect(DisplayProfiles.decode(try profiles.encoded()) == profiles)
    }

    @Test func corruptOrMissingDataGivesEmptyProfiles() {
        #expect(DisplayProfiles.decode(nil) == DisplayProfiles())
        #expect(DisplayProfiles.decode(Data("not json".utf8)) == DisplayProfiles())
    }

    @Test func unknownModeInStoredDataFallsBackToFollowGlobal() {
        let json = #"{"modes":{"\#(builtIn)":"holographic","\#(external)":"bar"}}"#
        let profiles = DisplayProfiles.decode(Data(json.utf8))
        #expect(profiles.mode(for: builtIn) == .followGlobal)
        #expect(profiles.mode(for: external) == .bar)
    }
}
