//
//  TargetDisplaySessionTests.swift
//  TrincanoTests
//

import CoreGraphics
import Testing

struct TargetDisplaySessionTests {
    // systemID is nil (some macOS 26 releases): the resolver falls back to the pointer.
    private let notebook = ActiveMenuBarDisplayResolver.Display(id: 1, frame: CGRect(x: 0, y: 0, width: 1470, height: 956))
    private let external = ActiveMenuBarDisplayResolver.Display(id: 2, frame: CGRect(x: -225, y: -1080, width: 1920, height: 1080))
    private let onExternal = CGPoint(x: 400, y: -500)
    private let onNotebook = CGPoint(x: 400, y: 10)

    private func resolve(pointer: CGPoint) -> UInt32 {
        ActiveMenuBarDisplayResolver.resolve(systemID: nil, displays: [notebook, external], pointer: pointer, mainID: 1)
    }

    @Test func targetStaysOnTheDisplayWhereTheSectionWasShown() {
        var session = TargetDisplaySession()
        var pointer = onExternal
        #expect(session.begin { resolve(pointer: pointer) } == 2)
        pointer = onNotebook                        // the cursor moves to the notebook's menu bar
        #expect(session.displayID(connected: [1, 2]) { resolve(pointer: pointer) } == 2)
    }

    @Test func targetStaysPinnedAcrossManyRehideTicks() {
        var session = TargetDisplaySession()
        var pointer = onExternal
        _ = session.begin { resolve(pointer: pointer) }
        for step in 0..<10 {
            pointer = step.isMultiple(of: 2) ? onNotebook : onExternal
            #expect(session.displayID(connected: [1, 2]) { resolve(pointer: pointer) } == 2)
        }
    }

    @Test func pinnedDisplayThatDisconnectedYieldsNoTarget() {
        var session = TargetDisplaySession()
        _ = session.begin { resolve(pointer: onExternal) }
        #expect(session.displayID(connected: [1]) { resolve(pointer: onNotebook) } == nil)
    }

    @Test func withoutASessionTheTargetFollowsTheResolver() {
        var session = TargetDisplaySession()
        #expect(session.displayID(connected: [1, 2]) { resolve(pointer: onExternal) } == 2)
        _ = session.begin { 1 }
        session.end()
        #expect(session.displayID(connected: [1, 2]) { resolve(pointer: onExternal) } == 2)
    }

    @Test func rehideAfterMovingToTheNotebookBarUsesTheExternalsGeometry() {
        // Wiring: the pinned display's frame goes to RehideGeometry. The pointer
        // is now in the notebook's menu bar, which is OUTSIDE the external's bar.
        var session = TargetDisplaySession()
        _ = session.begin { resolve(pointer: onExternal) }
        let targetID = session.displayID(connected: [1, 2]) { resolve(pointer: onNotebook) }
        let appKitExternal = CGRect(x: -225, y: 956, width: 1920, height: 1080)
        let appKitNotebook = CGRect(x: 0, y: 0, width: 1470, height: 956)
        let frame = targetID == 2 ? appKitExternal : appKitNotebook
        let visible = CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height - (targetID == 2 ? 24 : 32))
        let pointerInNotebookBar = CGPoint(x: 400, y: 940)
        #expect(RehideGeometry.isPointerOutsideMenuBar(pointer: pointerInNotebookBar, screenFrame: frame, visibleFrame: visible))
    }
}
