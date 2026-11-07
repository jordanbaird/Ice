//
//  DisplayTopologyTests.swift
//  TrincanoTests
//

import CoreGraphics
import Testing

struct DisplayTopologyTests {
    private func notebook(main: Bool = true, width: CGFloat = 1470) -> DisplayTopology.Display {
        .init(uuid: "N", frame: CGRect(x: 0, y: 0, width: width, height: 956), isBuiltIn: true, isMain: main)
    }
    private func external(main: Bool = false) -> DisplayTopology.Display {
        .init(uuid: "E", frame: CGRect(x: -225, y: 956, width: 1920, height: 1080), isBuiltIn: false, isMain: main)
    }

    @Test func connectingAnExternalMonitor() {
        let change = DisplayTopology.diff(old: [notebook()], new: [notebook(), external()])
        #expect(change.added == ["E"])
        #expect(change.removed.isEmpty)
        #expect(change.isEmpty == false)
    }

    @Test func disconnectingTheExternalMonitor() {
        let change = DisplayTopology.diff(old: [notebook(), external()], new: [notebook()])
        #expect(change.removed == ["E"])
        #expect(change.added.isEmpty)
    }

    @Test func changingTheMainDisplay() {
        let change = DisplayTopology.diff(
            old: [notebook(main: true), external(main: false)],
            new: [notebook(main: false), external(main: true)]
        )
        #expect(change.mainChanged)
        #expect(change.added.isEmpty && change.removed.isEmpty)
    }

    @Test func resolutionChangeIsAReconfiguration() {
        let change = DisplayTopology.diff(old: [notebook()], new: [notebook(width: 1280)])
        #expect(change.reconfigured == ["N"])
    }

    @Test func reorderedButIdenticalListIsNoChange() {
        let change = DisplayTopology.diff(old: [notebook(), external()], new: [external(), notebook()])
        #expect(change.isEmpty)
    }

    @Test func reactionsForConnectedDisconnectedAndMainChanges() {
        let connected = DisplayTopology.diff(old: [notebook()], new: [notebook(), external()])
        #expect(DisplayTopology.reactions(to: connected, barDisplayUUID: nil) == [.recache, .invalidateGeometry])

        let disconnected = DisplayTopology.diff(old: [notebook(), external()], new: [notebook()])
        #expect(DisplayTopology.reactions(to: disconnected, barDisplayUUID: "E") == [.recache, .invalidateGeometry, .hideBar])
        // The bar was on the notebook: it stays.
        #expect(DisplayTopology.reactions(to: disconnected, barDisplayUUID: "N") == [.recache, .invalidateGeometry])

        let none = DisplayTopology.diff(old: [notebook()], new: [notebook()])
        #expect(DisplayTopology.reactions(to: none, barDisplayUUID: "N").isEmpty)
    }

    @Test func resolutionChangeHidesNothingButRefreshesGeometry() {
        let change = DisplayTopology.diff(old: [notebook()], new: [notebook(width: 1280)])
        #expect(DisplayTopology.reactions(to: change, barDisplayUUID: "N") == [.recache, .invalidateGeometry])
    }
}
