//
//  RehideGeometryTests.swift
//  TrincanoTests
//

import CoreGraphics
import Testing

struct RehideGeometryTests {
    // Notebook below an external monitor (AppKit global, y up).
    private let notebookFrame = CGRect(x: 0, y: 0, width: 1470, height: 956)
    private let notebookVisible = CGRect(x: 0, y: 0, width: 1470, height: 924)       // 32 pt menu bar
    private let externalFrame = CGRect(x: -225, y: 956, width: 1920, height: 1080)
    private let externalVisible = CGRect(x: -225, y: 956, width: 1920, height: 1056)  // 24 pt menu bar

    private func outside(_ pointer: CGPoint, onExternal: Bool) -> Bool {
        RehideGeometry.isPointerOutsideMenuBar(
            pointer: pointer,
            screenFrame: onExternal ? externalFrame : notebookFrame,
            visibleFrame: onExternal ? externalVisible : notebookVisible
        )
    }

    @Test func pointerInsideTheTargetMenuBarDoesNotRehide() {
        #expect(outside(CGPoint(x: 500, y: 940), onExternal: false) == false)
        #expect(outside(CGPoint(x: 500, y: 2030), onExternal: true) == false)
    }

    @Test func pointerBelowTheTargetMenuBarRehides() {
        #expect(outside(CGPoint(x: 500, y: 400), onExternal: false))
        // On the external monitor (above the notebook), below its own menu bar.
        #expect(outside(CGPoint(x: 500, y: 1500), onExternal: true))
    }

    @Test func pointerOnAnotherScreenRehides() {
        // Target is the external's menu bar; the pointer is on the notebook.
        #expect(outside(CGPoint(x: 500, y: 940), onExternal: true))
        // Target is the notebook's menu bar; the pointer is on the external monitor.
        #expect(outside(CGPoint(x: 500, y: 2030), onExternal: false))
    }

    @Test func pointerBesideTheScreenDoesNotCountAsInsideItsMenuBar() {
        #expect(outside(CGPoint(x: -400, y: 940), onExternal: false))
    }
}
