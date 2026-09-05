//
//  NativeMenuBarDrag.swift
//  Ice
//

// Authorized diagnostic, NOT part of Ice. Sources: volume/fan/spotlight only.
// Targets add Ice. No prefs, prompts, taps, proxies, or process lifecycle control.
// Usage: snapshot | inspect name | check source left|right target | source left|right target [dwell] [settle]
// snapshot/inspect/check never send input. Do not use hardware/other UI automation
// during a drag. A source-side check is not physical-order/flicker acceptance.
// Stage checks allow only this tool's held left Command/left mouse. They cannot
// distinguish a user's simultaneous press of that same key/button. HID counters
// are used only before our first injected event: macOS includes our posts there.
// Dwell is limited to 0...0.2 s; held-input work has a 0.9 s safety deadline.
import AppKit
import ApplicationServices
import Darwin

private let allowedBundles = [
    "ice": "com.jordanbaird.Ice", "volume": "local.wenbo.AppVolumes",
    "fan": "com.crystalidea.macsfancontrol", "spotlight": "com.apple.campo",
]
private let windowServerExecutable = URL(
    fileURLWithPath: "/System/Library/PrivateFrameworks/SkyLight.framework/Resources/WindowServer"
).resolvingSymlinksInPath().path

private struct NativeItem {
    let name: String
    let pid: pid_t
    let element: AXUIElement
    let identifier: String?
    let frame: CGRect
}

private enum DragCheckError: Error {
    case invalidArgument, inputUnavailable, unexpectedInputState, applicationChanged
    case missingOrAmbiguousItem(String), invalidGeometry, unstableFrames, hitMismatch
    case eventCreationFailed, cursorUnavailable, sideNotVerified, dragDeadlineExceeded
}

private func attribute<T>(_ element: AXUIElement, _ key: String) -> T? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success else { return nil }
    return value as? T
}

private func finitePositive(_ rect: CGRect) -> Bool {
    [rect.minX, rect.minY, rect.width, rect.height].allSatisfy(\.isFinite) && rect.width > 0 && rect.height > 0
}

private func frame(of element: AXUIElement) -> CGRect? {
    guard let position: AXValue = attribute(element, kAXPositionAttribute),
          let dimensions: AXValue = attribute(element, kAXSizeAttribute) else { return nil }
    var origin = CGPoint.zero
    var size = CGSize.zero
    guard AXValueGetType(position) == .cgPoint, AXValueGetType(dimensions) == .cgSize,
          AXValueGetValue(position, .cgPoint, &origin), AXValueGetValue(dimensions, .cgSize, &size) else { return nil }
    let rect = CGRect(origin: origin, size: size)
    return finitePositive(rect) ? rect : nil
}

private func processID(of element: AXUIElement) -> pid_t? {
    var pid: pid_t = 0
    return AXUIElementGetPid(element, &pid) == .success ? pid : nil
}

@MainActor
private func uniqueApplication(_ bundle: String, expectedPID: pid_t? = nil) throws -> NSRunningApplication {
    let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).filter { !$0.isTerminated }
    guard apps.count == 1, let app = apps.first,
          expectedPID == nil || app.processIdentifier == expectedPID else { throw DragCheckError.applicationChanged }
    if bundle == allowedBundles["ice"], app.bundleURL?.standardizedFileURL.path != "/Applications/Ice.app" {
        throw DragCheckError.applicationChanged
    }
    return app
}

@MainActor
private func currentItems(named name: String) throws -> [NativeItem] {
    guard let bundle = allowedBundles[name] else { throw DragCheckError.invalidArgument }
    let app = try uniqueApplication(bundle)
    let root = AXUIElementCreateApplication(app.processIdentifier)
    AXUIElementSetMessagingTimeout(root, 0.25)
    guard let bar: AXUIElement = attribute(root, kAXExtrasMenuBarAttribute),
          let children: [AXUIElement] = attribute(bar, kAXChildrenAttribute) else { return [] }
    var result = [NativeItem]()
    for child in children {
        let identifier: String? = attribute(child, kAXIdentifierAttribute)
        if name == "ice", identifier != "Ice.ControlItem.Visible" { continue }
        guard let rect = frame(of: child) else { continue }
        // Only Ice's explicitly unique ID may deduplicate identical variants.
        if result.contains(where: {
            CFEqual($0.element, child) || (name == "ice" && $0.identifier == identifier && $0.frame == rect)
        }) { continue }
        result.append(NativeItem(
            name: name, pid: app.processIdentifier, element: child, identifier: identifier, frame: rect
        ))
    }
    return result
}

@MainActor
private func uniqueItem(_ name: String) throws -> NativeItem {
    let items = try currentItems(named: name)
    guard items.count == 1, let item = items.first else { throw DragCheckError.missingOrAmbiguousItem(name) }
    return item
}

private let physicalEventTypes: [CGEventType] = [
    .keyDown, .keyUp, .flagsChanged, .leftMouseDown, .leftMouseUp,
    .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp,
    .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .scrollWheel,
]

private func hardwareCounters() -> [UInt32] {
    physicalEventTypes.map { CGEventSource.counterForEventType(.hidSystemState, eventType: $0) }
}

private func ensureExpectedInputState(
    commandIsDown: Bool = false,
    mouseIsDown: Bool = false,
    counters: [UInt32]? = nil
) throws {
    // On this OS, HIDSystemState also reflects our cghid injections. Permit
    // only our already-posted inputs, never infer a physical source from them.
    let modifiers: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift, .maskSecondaryFn]
    let forbiddenModifiers = commandIsDown ? modifiers.subtracting(.maskCommand) : modifiers
    guard CGEventSource.flagsState(.hidSystemState).isDisjoint(with: forbiddenModifiers) else {
        throw DragCheckError.unexpectedInputState
    }
    for key in 0 ... 127 where CGEventSource.keyState(.hidSystemState, key: CGKeyCode(key)) {
        if commandIsDown, key == 55 { continue }
        throw DragCheckError.unexpectedInputState
    }
    for index in 0 ... 31 {
        if let button = CGMouseButton(rawValue: UInt32(index)),
           CGEventSource.buttonState(.hidSystemState, button: button) {
            if mouseIsDown, button == .left { continue }
            throw DragCheckError.unexpectedInputState
        }
    }
    if let counters, counters != hardwareCounters() { throw DragCheckError.unexpectedInputState }
}

@MainActor
private func validateGeometry(source: NativeItem, target: NativeItem, end: CGPoint, diagnostic: Bool = false) throws {
    let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
    let bars = windows.compactMap { window -> CGRect? in
        if diagnostic, window[kCGWindowName as String] as? String == "Menubar" {
            let owner = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value ?? 0
            print("Menubar owner=\(owner) path=\(processExecutablePath(owner) ?? "unavailable") layer=\(String(describing: window[kCGWindowLayer as String])) bounds=\(String(describing: window[kCGWindowBounds as String])) onscreen=\(String(describing: window[kCGWindowIsOnscreen as String]))")
        }
        guard let ownerPID = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
              processExecutablePath(ownerPID) == windowServerExecutable,
              window[kCGWindowName as String] as? String == "Menubar",
              (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 24,
              window[kCGWindowIsOnscreen as String] as? Bool == true,
              let dictionary = window[kCGWindowBounds as String] as? [String: Any],
              let rect = CGRect(dictionaryRepresentation: dictionary as CFDictionary),
              finitePositive(rect), (16 ... 64).contains(rect.height) else { return nil }
        return rect
    }
    let sameDisplay = NSScreen.screens.contains { screen in
        guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return false }
        let display = CGDisplayBounds(id)
        let strip = CGRect(x: display.minX, y: display.minY, width: display.width, height: 40)
        return strip.contains(source.frame) && strip.contains(target.frame) && strip.contains(end)
    }
    if diagnostic { print("Geometry source=\(source.frame) target=\(target.frame) end=\(end) sameDisplay=\(sameDisplay) validBars=\(bars)") }
    guard sameDisplay, abs(source.frame.midY - target.frame.midY) < 4,
          bars.contains(where: { $0.contains(source.frame) && $0.contains(target.frame) && $0.contains(end) }) else {
        throw DragCheckError.invalidGeometry
    }
}

private func processExecutablePath(_ pid: pid_t) -> String? {
    var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
    guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
    guard let path = String(bytes: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, encoding: .utf8) else { return nil }
    return URL(fileURLWithPath: path).resolvingSymlinksInPath().path
}

private func nativeHitMatches(_ item: NativeItem, diagnostic: Bool = false) -> Bool {
    let system = AXUIElementCreateSystemWide()
    AXUIElementSetMessagingTimeout(system, 0.25)
    var candidate: AXUIElement?
    guard AXUIElementCopyElementAtPosition(system, Float(item.frame.midX), Float(item.frame.midY), &candidate) == .success else { return false }
    var visited = [AXUIElement]()
    for depth in 0 ..< 5 {
        guard let node = candidate, !visited.contains(where: { CFEqual($0, node) }) else { break }
        visited.append(node)
        let identifier: String? = attribute(node, kAXIdentifierAttribute)
        let role: String? = attribute(node, kAXRoleAttribute)
        let pid = processID(of: node)
        let rect = frame(of: node)
        let sameObject = CFEqual(node, item.element)
        if diagnostic {
            print("  hit[\(depth)] pid=\(pid ?? 0) role=\(role ?? "nil") id=\(identifier ?? "nil") frame=\(String(describing: rect)) CFEqual=\(sameObject)")
        }
        // No display-title or geometry fallback. Ascend only a few parents to
        // find the exact source AX object, or its owner's same native ID/frame.
        if pid == item.pid, rect == item.frame,
           sameObject || (item.identifier?.isEmpty == false && identifier == item.identifier) {
            return true
        }
        candidate = attribute(node, kAXParentAttribute)
    }
    return false
}

@MainActor
private func report(_ label: String) {
    let pid = try? uniqueApplication("com.apple.MenuBarAgent").processIdentifier
    print("\(ISO8601DateFormatter().string(from: Date())) \(label) MenuBarAgent=\(pid ?? 0)")
    for name in ["volume", "fan", "ice", "spotlight"] {
        if let items = try? currentItems(named: name) {
            for item in items { print("  \(item.name) pid=\(item.pid) id=\(item.identifier ?? "nil"): \(item.frame)") }
        }
    }
    fflush(stdout)
}

@main
enum NativeMenuBarDrag {
    @MainActor
    static func main() {
        do { try run() } catch {
            fputs("STOPPED: \(error). No coordinate fallback/retry.\n", stderr)
            exit(1)
        }
    }

    @MainActor
    private static func run() throws {
        let rawArguments = Array(CommandLine.arguments.dropFirst())
        let readOnlyCheck = rawArguments.first == "check"
        let args = readOnlyCheck ? Array(rawArguments.dropFirst()) : rawArguments
        guard AXIsProcessTrusted() else { throw DragCheckError.inputUnavailable }
        if args == ["snapshot"] { report("snapshot (read-only)"); return }
        if args.count == 2, args[0] == "inspect", allowedBundles[args[1]] != nil {
            let item = try uniqueItem(args[1])
            print("Read-only \(item.name): pid=\(item.pid) id=\(item.identifier ?? "nil") \(item.frame)")
            print("Strict source hit match: \(nativeHitMatches(item, diagnostic: true))")
            return
        }
        guard (3 ... 5).contains(args.count), ["volume", "fan", "spotlight"].contains(args[0]),
              ["left", "right"].contains(args[1]), allowedBundles[args[2]] != nil,
              args[0] != args[2] else { throw DragCheckError.invalidArgument }
        let dwell = args.count >= 4 ? Double(args[3]) : 0
        let settle = args.count == 5 ? Double(args[4]) : 6
        guard let dwell, dwell.isFinite, (0 ... 0.2).contains(dwell),
              let settle, settle.isFinite, (0.3 ... 6).contains(settle) else { throw DragCheckError.invalidArgument }
        guard CGPreflightPostEventAccess() else { throw DragCheckError.inputUnavailable }
        try ensureExpectedInputState()
        let inputCounters = hardwareCounters()
        var commandIsDown = false
        var mouseIsDown = false
        var sentOwnInput = false
        var inputStateConflict = false
        var heldSince: UInt64?
        let icePID = try uniqueApplication("com.jordanbaird.Ice").processIdentifier
        let beforePID = try uniqueApplication("com.apple.MenuBarAgent").processIdentifier

        func ensureRuntime() throws {
            _ = try uniqueApplication("com.jordanbaird.Ice", expectedPID: icePID)
            _ = try uniqueApplication("com.apple.MenuBarAgent", expectedPID: beforePID)
            do {
                try ensureExpectedInputState(
                    commandIsDown: commandIsDown,
                    mouseIsDown: mouseIsDown,
                    counters: sentOwnInput ? nil : inputCounters
                )
            } catch {
                inputStateConflict = true
                throw error
            }
            if let heldSince, DispatchTime.now().uptimeNanoseconds - heldSince > 900_000_000 {
                throw DragCheckError.dragDeadlineExceeded
            }
        }
        let firstSource = try uniqueItem(args[0])
        let firstTarget = try uniqueItem(args[2])
        Thread.sleep(forTimeInterval: 0.15)
        try ensureRuntime()
        let item = try uniqueItem(args[0])
        let target = try uniqueItem(args[2])
        guard item.pid == firstSource.pid, target.pid == firstTarget.pid,
              CFEqual(item.element, firstSource.element), CFEqual(target.element, firstTarget.element),
              item.frame == firstSource.frame, target.frame == firstTarget.frame else { throw DragCheckError.unstableFrames }
        let start = CGPoint(x: item.frame.midX, y: item.frame.midY)
        let end = CGPoint(x: args[1] == "left" ? target.frame.minX - 3 : target.frame.maxX + 3, y: target.frame.midY)
        try validateGeometry(source: item, target: target, end: end, diagnostic: readOnlyCheck)
        guard nativeHitMatches(item), nativeHitMatches(target) else { throw DragCheckError.hitMismatch }
        if readOnlyCheck {
            try ensureRuntime()
            print("READ-ONLY CHECK PASSED: stable endpoints, strict hits, native WindowServer Menubar and display geometry; no input sent")
            return
        }
        guard let eventSource = CGEventSource(stateID: .combinedSessionState),
              let commandDown = CGEvent(keyboardEventSource: eventSource, virtualKey: 0x37, keyDown: true),
              let commandUp = CGEvent(keyboardEventSource: eventSource, virtualKey: 0x37, keyDown: false),
              let original = CGEvent(source: nil)?.location else { throw DragCheckError.eventCreationFailed }
        eventSource.localEventsSuppressionInterval = 0
        let permitted: CGEventFilterMask = [.permitLocalMouseEvents, .permitLocalKeyboardEvents, .permitSystemDefinedEvents]
        eventSource.setLocalEventsFilterDuringSuppressionState(permitted, state: .eventSuppressionStateRemoteMouseDrag)
        eventSource.setLocalEventsFilterDuringSuppressionState(permitted, state: .eventSuppressionStateSuppressionInterval)
        commandDown.flags = .maskCommand
        commandUp.flags = []
        func mouse(_ type: CGEventType, at point: CGPoint) throws -> CGEvent {
            guard let event = CGEvent(
                mouseEventSource: eventSource, mouseType: type, mouseCursorPosition: point, mouseButton: .left
            ) else { throw DragCheckError.eventCreationFailed }
            event.flags = [.maskCommand, .maskNonCoalesced]
            event.setIntegerValueField(.mouseEventClickState, value: 1)
            return event
        }
        // Construct EVERY event, especially releases, before posting any input.
        let mouseDown = try mouse(.leftMouseDown, at: start)
        let mouseUp = try mouse(.leftMouseUp, at: end)
        let dragEvents = try (1 ... 40).map { step in
            try mouse(.leftMouseDragged, at: CGPoint(x: start.x + (end.x - start.x) * CGFloat(step) / 40, y: start.y))
        }
        var cursorChanged = false
        var lastPoint = start
        defer {
            if mouseIsDown {
                mouseUp.location = lastPoint
                mouseUp.post(tap: .cghidEventTap)
            }
            if commandIsDown { commandUp.post(tap: .cghidEventTap) }
            // On a detected input conflict, release ours without warping back.
            if cursorChanged, !inputStateConflict { CGWarpMouseCursorPosition(original) }
        }
        try ensureRuntime()
        print("Validated \(args.joined(separator: " ")); Ice=\(icePID) MenuBarAgent=\(beforePID); no coordinate fallback")
        fflush(stdout)
        guard CGWarpMouseCursorPosition(start) == .success else { throw DragCheckError.cursorUnavailable }
        cursorChanged = true
        heldSince = DispatchTime.now().uptimeNanoseconds
        commandDown.post(tap: .cghidEventTap)
        sentOwnInput = true
        commandIsDown = true
        Thread.sleep(forTimeInterval: 0.05)
        try ensureRuntime()
        guard frame(of: item.element) == item.frame, frame(of: target.element) == target.frame,
              nativeHitMatches(item), nativeHitMatches(target) else { throw DragCheckError.hitMismatch }
        try ensureRuntime()
        mouseDown.post(tap: .cghidEventTap)
        mouseIsDown = true
        Thread.sleep(forTimeInterval: 0.08)
        for event in dragEvents {
            try ensureRuntime()
            event.post(tap: .cghidEventTap)
            lastPoint = event.location
            Thread.sleep(forTimeInterval: 0.01)
        }
        for _ in 0 ..< Int(ceil(dwell / 0.01)) {
            try ensureRuntime()
            Thread.sleep(forTimeInterval: 0.01)
        }
        try ensureRuntime()
        mouseUp.post(tap: .cghidEventTap)
        mouseIsDown = false
        commandUp.post(tap: .cghidEventTap)
        commandIsDown = false
        heldSince = nil
        if !inputStateConflict { CGWarpMouseCursorPosition(original) }
        cursorChanged = false
        for _ in 0 ..< Int(ceil(settle / 0.1)) {
            Thread.sleep(forTimeInterval: 0.1)
            try ensureRuntime() // Missing PID is inconclusive, not a proven crash.
        }
        let sourceAfter = try uniqueItem(args[0])
        let targetAfter = try uniqueItem(args[2])
        let correctSide = args[1] == "left" ? sourceAfter.frame.minX < targetAfter.frame.minX
            : sourceAfter.frame.minX > targetAfter.frame.minX
        report(correctSide ? "Native side matches; inspect actual bar separately" : "Native side does not match")
        if !correctSide { throw DragCheckError.sideNotVerified }
    }
}
