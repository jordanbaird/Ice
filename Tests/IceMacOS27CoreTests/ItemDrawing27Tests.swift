import CoreGraphics
import Testing
@testable import IceMacOS27Core

@Suite("ItemDrawing27")
struct ItemDrawing27Tests {
    // Measured on macOS 27.0: the external display is primary, the built-in one sits to its left.
    let external = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    let builtIn = CGRect(x: -1512, y: 98, width: 1512, height: 982)

    @Test("An item on the active menu bar is drawn")
    func drawn() {
        #expect(ItemDrawing27.isDrawn(itemFrame: CGRect(x: 1478, y: 2, width: 33, height: 24), activeDisplayBounds: external, chevronFrame: nil))
    }

    @Test("A concealed item's frame left on the other display is not drawn")
    func otherDisplay() {
        #expect(!ItemDrawing27.isDrawn(itemFrame: CGRect(x: -651, y: 102, width: 42, height: 24), activeDisplayBounds: external, chevronFrame: nil))
    }

    @Test("An item folded behind the overflow button is not drawn")
    func folded() {
        let chevron = CGRect(x: -619, y: 99, width: 17, height: 30)
        #expect(!ItemDrawing27.isDrawn(itemFrame: CGRect(x: -649, y: 102, width: 47, height: 24), activeDisplayBounds: builtIn, chevronFrame: chevron))
    }

    @Test("Without a known active display only the overflow button decides")
    func unknownDisplay() {
        #expect(ItemDrawing27.isDrawn(itemFrame: CGRect(x: -442, y: 102, width: 33, height: 24), activeDisplayBounds: nil, chevronFrame: nil))
    }
}
