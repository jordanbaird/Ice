// Moves the pointer with real mouse-moved events, for the macOS 27 verification scripts.
// usage: pointer glide <x> <y> [steps] | pointer hold <seconds> | pointer where
import CoreGraphics
import Foundation

let arguments = CommandLine.arguments
let source = CGEventSource(stateID: .hidSystemState)

func post(_ point: CGPoint) {
    CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?
        .post(tap: .cghidEventTap)
}

let current = CGEvent(source: nil)?.location ?? .zero
switch arguments.dropFirst().first {
case "glide":
    let target = CGPoint(x: Double(arguments[2])!, y: Double(arguments[3])!)
    let steps = arguments.count > 4 ? Int(arguments[4])! : 40
    for step in 1...steps {
        let t = CGFloat(step) / CGFloat(steps)
        post(CGPoint(x: current.x + (target.x - current.x) * t, y: current.y + (target.y - current.y) * t))
        usleep(12_000)
    }
case "hold":
    let end = Date().addingTimeInterval(Double(arguments[2])!)
    while Date() < end {
        post(current)
        usleep(50_000)
    }
case "where":
    print("\(Int(current.x)) \(Int(current.y))")
default:
    FileHandle.standardError.write("usage: pointer glide <x> <y> [steps] | hold <seconds> | where\n".data(using: .utf8)!)
    exit(2)
}
