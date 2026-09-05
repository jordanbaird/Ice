// README — narrowly scoped manual regression tool, NOT part of the Ice target.
// Build with SDK 27:
//   xcrun swiftc -parse-as-library Tests/NativeIceMouseToggleProbe.swift -o <probe>
// Usage: <probe> <click-count: 1...20> <interval-ms: 40...1000>
//
// Manually unlock the Mac first. Do not use the mouse/keyboard concurrently;
// do not run other UI automation while this tool runs. The pointer is saved and
// restored on normal completion or a failed safety check. The tool never unlocks
// the computer, requests permissions, manipulates another menu item, changes
// preferences, or installs an event tap. Terminating it externally can prevent
// cleanup; keep each run short and let it finish.
//
// Only the unique running /Applications/Ice.app (com.jordanbaird.Ice) is allowed.
// Before EVERY click, rediscover its exact Ice.ControlItem.Visible AX extra;
// require a finite, positive frame no wider than 40 points inside an on-screen
// native Menubar window; require system-wide hit testing at its center to return
// that same identifier AND Ice's PID. Failure stops rather than falling back to
// a stale coordinate, another process, or another item. No coordinate/PID/path
// arguments are accepted. Permission checks are preflight-only, never prompts.
//
// Sends plain leftMouseDown/leftMouseUp only: clickState=1, flags=[], roughly
// 2 ms between down and up. The native status button activates on mouseUp.
// No keyboard events, drags, mouse-moved events, or global event taps are used.
// Requested spacing is down-to-down, subject to validation/scheduling overhead.
// Logs show monotonic timestamps around the actual CGEvent.post calls and their
// intervals. They are NOT acknowledgement or render/animation latency. Observe
// the real menu bar separately: every click must reverse visibility; final
// parity alone is insufficient. The tool does not take screenshots or claim QA
// passed simply because all posts completed.

import AppKit
import ApplicationServices

private enum ProbeError: Error, CustomStringConvertible {
    case invalidArguments
    case permissionsUnavailable
    case applicationUnavailable
    case buttonUnavailable
    case invalidFrame
    case menuBarUnavailable
    case hitTestMismatch
    case physicalInputActive
    case eventCreationFailed

    var description: String {
        switch self {
        case .invalidArguments: "Usage: <probe> <click-count: 1...20> <interval-ms: 40...1000>"
        case .permissionsUnavailable: "Required AX/post-event permission is unavailable; no prompt requested."
        case .applicationUnavailable: "Exactly one running /Applications/Ice.app with the expected identity is required."
        case .buttonUnavailable: "Exactly one enabled Ice.ControlItem.Visible AX extra is required."
        case .invalidFrame: "Ice's current button frame is invalid or wider than 40 points."
        case .menuBarUnavailable: "Ice's button is not wholly inside a visible native Menubar strip."
        case .hitTestMismatch: "System-wide hit test did not identify this Ice PID and exact Visible button."
        case .physicalInputActive: "A mouse button or keyboard modifier is down; stop concurrent input."
        case .eventCreationFailed: "Cannot create the required cursor/event state."
        }
    }
}

private func attribute<T>(_ element: AXUIElement, _ key: String) -> T? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success else { return nil }
    return value as? T
}

private func finitePositive(_ frame: CGRect) -> Bool {
    [frame.origin.x, frame.origin.y, frame.width, frame.height].allSatisfy(\.isFinite)
        && frame.width > 0 && frame.height > 0
}

@MainActor
private func iceApplication(expectedPID: pid_t? = nil) throws -> NSRunningApplication {
    let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.jordanbaird.Ice")
    guard apps.count == 1, let app = apps.first,
          !app.isTerminated,
          app.bundleURL?.standardizedFileURL.path == "/Applications/Ice.app",
          expectedPID == nil || app.processIdentifier == expectedPID else {
        throw ProbeError.applicationUnavailable
    }
    return app
}

private func ensureNoPhysicalInput() throws {
    let flags = CGEventSource.flagsState(.hidSystemState)
    let modifiers: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift, .maskSecondaryFn]
    guard flags.intersection(modifiers).isEmpty,
          !CGEventSource.buttonState(.hidSystemState, button: .left),
          !CGEventSource.buttonState(.hidSystemState, button: .right),
          !CGEventSource.buttonState(.hidSystemState, button: .center) else {
        throw ProbeError.physicalInputActive
    }
}

@MainActor
private func validatedPoint(expectedPID: pid_t) throws -> CGPoint {
    guard AXIsProcessTrusted(), CGPreflightPostEventAccess() else { throw ProbeError.permissionsUnavailable }
    try ensureNoPhysicalInput()
    let app = try iceApplication(expectedPID: expectedPID)
    let root = AXUIElementCreateApplication(app.processIdentifier)
    AXUIElementSetMessagingTimeout(root, 0.25)
    guard let extras: AXUIElement = attribute(root, kAXExtrasMenuBarAttribute),
          let children: [AXUIElement] = attribute(extras, kAXChildrenAttribute) else {
        throw ProbeError.buttonUnavailable
    }
    let matches = children.filter {
        attribute($0, kAXIdentifierAttribute) as String? == "Ice.ControlItem.Visible"
    }
    guard matches.count == 1, let button = matches.first,
          attribute(button, kAXEnabledAttribute) as Bool? == true,
          let position: AXValue = attribute(button, kAXPositionAttribute),
          let dimensions: AXValue = attribute(button, kAXSizeAttribute) else {
        throw ProbeError.buttonUnavailable
    }
    var point = CGPoint.zero
    var size = CGSize.zero
    guard AXValueGetValue(position, .cgPoint, &point), AXValueGetValue(dimensions, .cgSize, &size) else {
        throw ProbeError.invalidFrame
    }
    let frame = CGRect(origin: point, size: size)
    guard finitePositive(frame), frame.width <= 40, frame.height <= 64 else { throw ProbeError.invalidFrame }

    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    let menuBarContainsButton = windows.contains { window in
        guard window[kCGWindowName as String] as? String == "Menubar",
              window[kCGWindowIsOnscreen as String] as? Bool == true,
              let bounds = window[kCGWindowBounds as String] as? [String: Any],
              let strip = CGRect(dictionaryRepresentation: bounds as CFDictionary),
              finitePositive(strip), strip.width >= 200,
              (16 ... 64).contains(strip.height) else { return false }
        return strip.contains(frame)
    }
    guard menuBarContainsButton else { throw ProbeError.menuBarUnavailable }

    let center = CGPoint(x: frame.midX, y: frame.midY)
    let system = AXUIElementCreateSystemWide()
    AXUIElementSetMessagingTimeout(system, 0.25)
    var hit: AXUIElement?
    guard AXUIElementCopyElementAtPosition(system, Float(center.x), Float(center.y), &hit) == .success,
          let hit, attribute(hit, kAXIdentifierAttribute) as String? == "Ice.ControlItem.Visible" else {
        throw ProbeError.hitTestMismatch
    }
    var hitPID: pid_t = 0
    guard AXUIElementGetPid(hit, &hitPID) == .success, hitPID == expectedPID else {
        throw ProbeError.hitTestMismatch
    }
    return center
}

@main
enum NativeIceMouseToggleProbe {
    @MainActor
    static func main() {
        do {
            try run()
        } catch {
            fputs("Stopped: \(error)\n", stderr)
            exit(1)
        }
    }

    @MainActor
    private static func run() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.count == 2,
              let count = Int(arguments[0]), (1 ... 20).contains(count),
              let intervalMS = Double(arguments[1]), intervalMS.isFinite,
              (40 ... 1000).contains(intervalMS) else { throw ProbeError.invalidArguments }
        guard AXIsProcessTrusted(), CGPreflightPostEventAccess() else { throw ProbeError.permissionsUnavailable }
        let app = try iceApplication()
        guard let originalCursor = CGEvent(source: nil)?.location,
              let source = CGEventSource(stateID: .combinedSessionState) else { throw ProbeError.eventCreationFailed }
        source.localEventsSuppressionInterval = 0
        var sentAnyEvent = false
        defer {
            if sentAnyEvent {
                let result = CGWarpMouseCursorPosition(originalCursor)
                if result != .success { fputs("Warning: cursor restore returned \(result.rawValue).\n", stderr) }
            }
        }

        print("Ice PID \(app.processIdentifier); \(count) plain left clicks; requested down-to-down interval \(intervalMS) ms")
        print("Monotonic post-call timings below are NOT rendering latency or proof of visible toggles.")
        fflush(stdout)
        let start = DispatchTime.now().uptimeNanoseconds
        var previousDown: UInt64?
        for index in 0 ..< count {
            if let previousDown {
                let elapsedMS = Double(DispatchTime.now().uptimeNanoseconds - previousDown) / 1_000_000
                if elapsedMS < intervalMS { Thread.sleep(forTimeInterval: (intervalMS - elapsedMS) / 1000) }
            }
            let center = try validatedPoint(expectedPID: app.processIdentifier)
            guard let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown,
                                     mouseCursorPosition: center, mouseButton: .left),
                  let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp,
                                   mouseCursorPosition: center, mouseButton: .left) else {
                throw ProbeError.eventCreationFailed
            }
            for event in [down, up] {
                event.flags = []
                event.setIntegerValueField(.mouseEventClickState, value: 1)
            }
            let downTime = DispatchTime.now().uptimeNanoseconds
            down.timestamp = downTime
            down.post(tap: .cghidEventTap)
            sentAnyEvent = true
            Thread.sleep(forTimeInterval: 0.002)
            let upTime = DispatchTime.now().uptimeNanoseconds
            up.timestamp = upTime
            up.post(tap: .cghidEventTap)
            let afterUp = DispatchTime.now().uptimeNanoseconds
            let actualInterval = previousDown.map { String(format: "%.3f", Double(downTime - $0) / 1_000_000) } ?? "n/a"
            print(String(format: "click %d: down=%.3f ms; up=%.3f ms; down-up=%.3f ms; post-complete=%.3f ms; down interval=%@ ms; point=(%.1f, %.1f)",
                         index + 1, Double(downTime - start) / 1_000_000, Double(upTime - start) / 1_000_000,
                         Double(upTime - downTime) / 1_000_000, Double(afterUp - start) / 1_000_000,
                         actualInterval, center.x, center.y))
            fflush(stdout)
            previousDown = downTime
        }
        print("All post calls completed. Inspect every physical menu-bar transition separately; final parity is not sufficient.")
        fflush(stdout)
    }
}
