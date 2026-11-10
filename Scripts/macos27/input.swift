// usage: input click | input escape | input drag <x1> <y1> <x2> <y2> | input close-window
// Posts real input events: a click at the pointer, Escape, a drag, or Command-W.
//
// The tool waits before it exits: events posted right before a process exits are dropped
// (measured on macOS 27.0: an Escape posted that way never reached any application, and
// the mouse-up of a click was sometimes lost).
import CoreGraphics
import Foundation

let arguments = CommandLine.arguments
let source = CGEventSource(stateID: .hidSystemState)
defer { usleep(250_000) }

func mouse(_ type: CGEventType, _ point: CGPoint) {
    CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
}

func key(_ code: CGKeyCode, flags: CGEventFlags = []) {
    for down in [true, false] {
        let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)
        event?.flags = flags
        event?.post(tap: .cghidEventTap)
        usleep(30_000)
    }
}

switch arguments[1] {
case "click":
    let point = CGEvent(source: nil)?.location ?? .zero
    mouse(.leftMouseDown, point); usleep(60_000); mouse(.leftMouseUp, point)
case "escape":
    key(53)
case "close-window":
    key(13, flags: .maskCommand)
case "drag":
    let from = CGPoint(x: Double(arguments[2])!, y: Double(arguments[3])!)
    let to = CGPoint(x: Double(arguments[4])!, y: Double(arguments[5])!)
    mouse(.mouseMoved, from); usleep(200_000)
    mouse(.leftMouseDown, from); usleep(300_000)
    for step in 1...30 {
        let t = CGFloat(step) / 30
        mouse(.leftMouseDragged, CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t))
        usleep(20_000)
    }
    usleep(300_000)
    mouse(.leftMouseUp, to)
default:
    FileHandle.standardError.write("usage: input click | escape | drag x1 y1 x2 y2 | close-window\n".data(using: .utf8)!)
    exit(2)
}
