//
//  ActiveMenuBarDisplayResolverTests.swift
//  TrincanoTests
//

import CoreGraphics
import Testing

struct ActiveMenuBarDisplayResolverTests {
    // The Paulo's setup: the notebook is the main display, an external monitor sits above it.
    private let notebook = ActiveMenuBarDisplayResolver.Display(id: 1, frame: CGRect(x: 0, y: 0, width: 1470, height: 956))
    private let externalAbove = ActiveMenuBarDisplayResolver.Display(id: 2, frame: CGRect(x: -225, y: -1080, width: 1920, height: 1080))

    private func resolve(system: UInt32?, pointer: CGPoint?, main: UInt32 = 1) -> UInt32 {
        ActiveMenuBarDisplayResolver.resolve(
            systemID: system, displays: [notebook, externalAbove], pointer: pointer, mainID: main
        )
    }

    @Test func trustsTheSystemAnswerWhenItIsAnActiveDisplay() {
        #expect(resolve(system: 2, pointer: CGPoint(x: 100, y: 100)) == 2)
        #expect(resolve(system: 1, pointer: CGPoint(x: 100, y: -500)) == 1)
    }

    @Test func fallsBackToTheDisplayUnderThePointerNotTheMainDisplay() {
        // The limit left by #922: with the system call returning nil the main
        // display was used even when the user is working on the external one.
        #expect(resolve(system: nil, pointer: CGPoint(x: 400, y: -500)) == 2)
        #expect(resolve(system: nil, pointer: CGPoint(x: 400, y: 400)) == 1)
    }

    @Test func staleSystemIDOfADisconnectedDisplayFallsBackToThePointer() {
        #expect(resolve(system: 99, pointer: CGPoint(x: 400, y: -500)) == 2)
    }

    @Test func fallsBackToMainWithoutAPointerOrOutsideEveryDisplay() {
        #expect(resolve(system: nil, pointer: nil) == 1)
        #expect(resolve(system: nil, pointer: CGPoint(x: 9000, y: 9000)) == 1)
    }

    @Test func pointerOnTheSharedEdgeBelongsToExactlyOneDisplay() {
        // y == 0 is the notebook's top edge and the external's bottom edge.
        let result = resolve(system: nil, pointer: CGPoint(x: 400, y: 0))
        #expect(result == 1)
    }

    @Test func mainDisplayCanBeTheExternalOne() {
        #expect(resolve(system: nil, pointer: nil, main: 2) == 2)
    }
}
