import CoreGraphics
import Foundation
import Testing
@testable import IceMacOS27Core

@Suite("RememberedItems27")
struct RememberedItems27Tests {
    let withTitle = RememberedItem27(
        tag: "Item-0",
        windowID: 2_574_467_248,
        bounds: CGRect(x: -915, y: 102, width: 47, height: 24),
        title: "Docker Desktop"
    )
    let withoutTitle = RememberedItem27(
        tag: "Item-1",
        windowID: 2_283_167_732,
        bounds: CGRect(x: 1205, y: 2, width: 36, height: 24),
        title: nil
    )

    @Test("A record survives encoding and decoding unchanged")
    func roundTrip() {
        let items = ["com.electron.dockerdesktop": [withTitle, withoutTitle]]
        #expect(RememberedItems27.decode(RememberedItems27.encode(items)) == items)
    }

    @Test("The signature ignores where an item is drawn")
    func signatureIgnoresPosition() {
        var moved = withTitle
        moved.bounds = CGRect(x: -1084, y: 102, width: 47, height: 24)
        #expect(
            RememberedItems27.signature(of: ["a": [withTitle]])
                == RememberedItems27.signature(of: ["a": [moved]])
        )
    }

    @Test("The signature changes when an item appears")
    func signatureNoticesANewItem() {
        #expect(
            RememberedItems27.signature(of: ["a": [withTitle]])
                != RememberedItems27.signature(of: ["a": [withTitle, withoutTitle]])
        )
    }

    /// Review Focus 4. The store is read back from a preference file that another version of
    /// Ice, or a person with a plist editor, may have left in any shape at all.
    @Test("A malformed record is dropped and the rest survive")
    func malformedRecordsAreDropped() {
        let stored: [String: [[String: Any]]] = [
            "com.electron.dockerdesktop": [
                ["tag": "Item-0", "windowID": NSNumber(value: UInt32(7)), "x": 1.0, "y": 2.0, "width": 3.0, "height": 4.0],
                ["windowID": NSNumber(value: UInt32(8)), "x": 1.0, "y": 2.0, "width": 3.0, "height": 4.0],
                ["tag": "Item-2", "windowID": "not a number", "x": 1.0, "y": 2.0, "width": 3.0, "height": 4.0],
            ],
            "com.electron.pritunl": [
                ["tag": "Item-0", "windowID": NSNumber(value: UInt32(9)), "x": 5.0, "y": 6.0, "width": 7.0, "height": 8.0],
            ],
        ]
        let decoded = RememberedItems27.decode(stored)
        #expect(decoded["com.electron.dockerdesktop"]?.count == 1)
        #expect(decoded["com.electron.dockerdesktop"]?.first?.tag == "Item-0")
        #expect(decoded["com.electron.pritunl"]?.count == 1)
    }

    /// The store is read back as `[String: Any]` and cast whole in the caller, so one
    /// application's entry in the wrong shape used to fail the cast and lose every other
    /// application with it — silently, and for the rest of the session.
    @Test("An application whose entry is not a list of records costs only that application")
    func aMalformedEntryCostsOnlyItself() {
        let stored: [String: Any] = [
            "com.electron.dockerdesktop": "not a list at all",
            "com.electron.pritunl": [
                ["tag": "Item-0", "windowID": NSNumber(value: UInt32(9)), "x": 5.0, "y": 6.0, "width": 7.0, "height": 8.0],
            ],
        ]
        let decoded = RememberedItems27.decode(anyStored: stored)
        #expect(decoded["com.electron.dockerdesktop"] == nil)
        #expect(decoded["com.electron.pritunl"]?.count == 1)
    }

    @Test("An application whose records are all malformed is left out")
    func anApplicationWithNothingLeftIsDropped() {
        let stored: [String: [[String: Any]]] = ["com.electron.dockerdesktop": [["tag": "Item-0"]]]
        #expect(RememberedItems27.decode(stored).isEmpty)
    }
}
