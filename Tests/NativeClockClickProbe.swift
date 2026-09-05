// Narrow manual QA helper, not part of Ice. Usage: <probe> [right]. No arguments
// sends one plain left click; literal "right" sends one plain right click at
// the main-display clock only. The candidate comes from an inspected clock
// screenshot; it is NEVER used unless the live system-wide AX hit (or at most
// three parents) confirms the exact clock identifier, allowed owner and frame.
// No coordinate fallback, key events, drags, taps, permission requests,
// notification inspection or preference writes. Keep hands off input during
// this short test; the original cursor is restored after the paired click.
import AppKit
import ApplicationServices

private enum ClockProbeError: Error, CustomStringConvertible {
    case arguments
    case permissions
    case display
    case inputActive
    case targetMismatch
    case targetChanged
    case eventCreation

    var description: String {
        switch self {
        case .arguments: "Usage: <probe> [right]. Only one left/default or literal-right clock click is allowed."
        case .permissions: "AX/post-event preflight failed; no permission prompt was requested."
        case .display: "The main display or its top 40-point strip is unavailable."
        case .inputActive: "A physical mouse button or keyboard modifier is active; no click sent."
        case .targetMismatch: "The inspected point is not the exact native clock with an allowed owner and containing frame."
        case .targetChanged: "The live clock identity/frame changed during validation; no click sent."
        case .eventCreation: "Unable to create the paired events or save cursor state."
        }
    }
}

private func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
    return value as? T
}

private func frame(of element: AXUIElement) -> CGRect? {
    guard let position: AXValue = attribute(element, kAXPositionAttribute),
          let size: AXValue = attribute(element, kAXSizeAttribute),
          AXValueGetType(position) == .cgPoint, AXValueGetType(size) == .cgSize else { return nil }
    var origin = CGPoint.zero
    var dimensions = CGSize.zero
    guard AXValueGetValue(position, .cgPoint, &origin), AXValueGetValue(size, .cgSize, &dimensions) else { return nil }
    let rect = CGRect(origin: origin, size: dimensions)
    guard [rect.minX, rect.minY, rect.width, rect.height].allSatisfy(\.isFinite),
          rect.width > 0, rect.height > 0 else { return nil }
    return rect
}

private func ensureNoPhysicalInput() throws {
    let modifiers: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift, .maskSecondaryFn, .maskHelp]
    guard CGEventSource.flagsState(.hidSystemState).intersection(modifiers).isEmpty else {
        throw ClockProbeError.inputActive
    }
    for key in [54, 55, 56, 57, 58, 59, 60, 61, 62, 63] {
        if CGEventSource.keyState(.hidSystemState, key: CGKeyCode(key)) { throw ClockProbeError.inputActive }
    }
    for code in 0 ..< 32 {
        if let button = CGMouseButton(rawValue: UInt32(code)),
           CGEventSource.buttonState(.hidSystemState, button: button) { throw ClockProbeError.inputActive }
    }
}

private struct ClockTarget: Equatable {
    let pid: pid_t
    let frame: CGRect
    let point: CGPoint
}

@MainActor
private func validatedClock() throws -> ClockTarget {
    guard AXIsProcessTrusted(), CGPreflightPostEventAccess() else { throw ClockProbeError.permissions }
    try ensureNoPhysicalInput()
    let display = CGMainDisplayID()
    let bounds = CGDisplayBounds(display)
    guard CGDisplayIsActive(display) != 0,
          [bounds.minX, bounds.minY, bounds.width, bounds.height].allSatisfy(\.isFinite),
          bounds.width >= 300, bounds.height >= 40 else { throw ClockProbeError.display }
    let strip = CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: 40)
    let point = CGPoint(x: bounds.maxX - 78, y: bounds.minY + 16)
    guard strip.contains(point) else { throw ClockProbeError.display }

    let system = AXUIElementCreateSystemWide()
    AXUIElementSetMessagingTimeout(system, 0.25)
    var candidate: AXUIElement?
    guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &candidate) == .success else {
        throw ClockProbeError.targetMismatch
    }
    let allowedOwners = Set(["com.apple.MenuBarAgent", "com.apple.controlcenter"])
    for depth in 0 ... 3 {
        guard let element = candidate else { break }
        AXUIElementSetMessagingTimeout(element, 0.25)
        if attribute(element, kAXIdentifierAttribute) as String? == "com.apple.menuextra.clock" {
            var pid: pid_t = 0
            guard AXUIElementGetPid(element, &pid) == .success,
                  let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated,
                  let bundleID = app.bundleIdentifier, allowedOwners.contains(bundleID),
                  let currentFrame = frame(of: element), currentFrame.contains(point), strip.contains(currentFrame) else {
                throw ClockProbeError.targetMismatch
            }
            return ClockTarget(pid: pid, frame: currentFrame, point: point)
        }
        if depth < 3 { candidate = attribute(element, kAXParentAttribute) }
    }
    throw ClockProbeError.targetMismatch
}

@main
enum NativeClockClickProbe {
    @MainActor
    static func main() {
        do { try run() } catch {
            fputs("Stopped: \(error)\n", stderr)
            exit(1)
        }
    }

    @MainActor
    private static func run() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.isEmpty || arguments == ["right"] else { throw ClockProbeError.arguments }
        let isRight = arguments == ["right"]
        let target = try validatedClock()
        guard let originalCursor = CGEvent(source: nil)?.location,
              let source = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(mouseEventSource: source, mouseType: isRight ? .rightMouseDown : .leftMouseDown,
                                 mouseCursorPosition: target.point, mouseButton: isRight ? .right : .left),
              let up = CGEvent(mouseEventSource: source, mouseType: isRight ? .rightMouseUp : .leftMouseUp,
                               mouseCursorPosition: target.point, mouseButton: isRight ? .right : .left) else {
            throw ClockProbeError.eventCreation
        }
        source.localEventsSuppressionInterval = 0
        for event in [down, up] {
            event.flags = []
            event.setIntegerValueField(.mouseEventClickState, value: 1)
        }
        guard try validatedClock() == target else { throw ClockProbeError.targetChanged }
        try ensureNoPhysicalInput()
        defer {
            let result = CGWarpMouseCursorPosition(originalCursor)
            if result != .success { fputs("Warning: cursor restoration returned \(result.rawValue).\n", stderr) }
        }
        print("Verified native clock PID=\(target.pid), frame=\(target.frame), point=\(target.point)")
        down.timestamp = DispatchTime.now().uptimeNanoseconds
        down.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.002)
        up.timestamp = DispatchTime.now().uptimeNanoseconds
        up.post(tap: .cghidEventTap)
        print("Posted one paired plain \(isRight ? "right" : "left") click. Verify native clock behavior separately; Ice must not receive it.")
    }
}
