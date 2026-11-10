import CoreGraphics
import Testing
@testable import IceMacOS27Core

@Suite("CaptureIndicator27")
struct CaptureIndicator27Tests {
    let bar = CGRect(x: 0, y: 1050, width: 1920, height: 30)

    @Test("The camera wins over the microphone")
    func cameraWins() {
        #expect(CaptureIndicator27.kind(cameraInUse: true, microphoneInUse: true) == .camera)
        #expect(CaptureIndicator27.kind(cameraInUse: true, microphoneInUse: false) == .camera)
    }

    @Test("The microphone alone is shown as the microphone")
    func microphoneAlone() {
        #expect(CaptureIndicator27.kind(cameraInUse: false, microphoneInUse: true) == .microphone)
    }

    @Test("Nothing in use, nothing to say")
    func nothing() {
        #expect(CaptureIndicator27.kind(cameraInUse: false, microphoneInUse: false) == nil)
    }

    @Test("The indicator sits left of the items, in the bar")
    func besideTheItems() {
        let frame = CaptureIndicator27.frame(barFrame: bar, leftEdgeOfItems: 1400, width: 34, gap: 6)
        #expect(frame == CGRect(x: 1360, y: 1050, width: 34, height: 30))
    }

    @Test("A bar with no items keeps it at the right end")
    func noItems() {
        let frame = CaptureIndicator27.frame(barFrame: bar, leftEdgeOfItems: nil, width: 34, gap: 6)
        #expect(frame.maxX == bar.maxX - 6)
        #expect(frame.height == bar.height)
    }

    @Test("It never runs off the left of the bar")
    func staysOnTheBar() {
        let frame = CaptureIndicator27.frame(barFrame: bar, leftEdgeOfItems: 10, width: 34, gap: 6)
        #expect(frame.minX == bar.minX)
    }

    @Test("A bar at negative coordinates is no different")
    func builtInDisplay() {
        let builtIn = CGRect(x: -1512, y: 950, width: 1512, height: 33)
        let frame = CaptureIndicator27.frame(barFrame: builtIn, leftEdgeOfItems: -300, width: 34, gap: 6)
        #expect(frame == CGRect(x: -340, y: 950, width: 34, height: 33))
    }
}
