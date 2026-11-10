// Measures how short the concealment lift around a replayed click can be before the clock
// stops opening Notification Center, on each display.
//
// Ice lifts concealment so MenuBarAgent will accept the click, then puts it back. Every
// millisecond of the lift is a millisecond of the bar moving, and the movement is what makes
// the panel's animation stutter — so the lift wants to be as short as it can be without
// losing clicks.
//
// usage: clock-restore [repetitions] [delay ...]      (delays in milliseconds)
// Requirements: Ice installed and running, Thaw not running. Takes the pointer.
import AppKit
import ApplicationServices

func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success ? value : nil
}

func elements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement]? {
    value(element, attribute) as? [AXUIElement]
}

func frame(_ element: AXUIElement) -> CGRect {
    var position = CGPoint.zero
    var size = CGSize.zero
    if let v = value(element, kAXPositionAttribute) { AXValueGetValue(v as! AXValue, .cgPoint, &position) }
    if let v = value(element, kAXSizeAttribute) { AXValueGetValue(v as! AXValue, .cgSize, &size) }
    return CGRect(origin: position, size: size)
}

/// The windows on screen, as Ice judges a panel by them.
func panelWindows() -> [(number: Int, layer: Int, height: CGFloat)] {
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    return list.compactMap { window in
        guard
            let number = window[kCGWindowNumber as String] as? Int,
            let layer = window[kCGWindowLayer as String] as? Int,
            let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
            let height = bounds["Height"]
        else {
            return nil
        }
        return (number, layer, height)
    }
}

/// A new tall window at or above the menu bar's level means the panel opened (measured on
/// macOS 27.0: Notification Center stands at layer 21, Control Centre at 101).
func openedPanel(before: Set<Int>) -> Int? {
    panelWindows().first { !before.contains($0.number) && $0.layer >= 20 && $0.height > 150 }?.number
}

let source = CGEventSource(stateID: .hidSystemState)

func click(_ point: CGPoint) {
    for type in [CGEventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
        CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?
            .post(tap: .cghidEventTap)
        usleep(40_000)
    }
}

func pressEscape() {
    for down in [true, false] {
        CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: down)?.post(tap: .cghidEventTap)
        usleep(30_000)
    }
}

/// The clock of each display: MenuBarAgent keeps one window per display, and the clock is
/// the widest of the system items in it.
func clocksByDisplay() -> [CGDirectDisplayID: CGRect] {
    guard let agent = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.MenuBarAgent").first else {
        return [:]
    }
    let application = AXUIElementCreateApplication(agent.processIdentifier)
    var framesByDisplay = [CGDirectDisplayID: [CGRect]]()
    for window in elements(application, kAXWindowsAttribute) ?? [] {
        for child in elements(window, kAXChildrenAttribute) ?? [] {
            let hosted = elements(child, kAXChildrenAttribute)?.first ?? child
            let itemFrame = frame(hosted)
            guard itemFrame.width > 0 else {
                continue
            }
            var display = CGDirectDisplayID(0)
            var matches: UInt32 = 0
            CGGetDisplaysWithPoint(CGPoint(x: itemFrame.midX, y: itemFrame.midY), 1, &display, &matches)
            guard matches > 0 else {
                continue
            }
            framesByDisplay[display, default: []].append(itemFrame)
        }
    }
    return framesByDisplay.compactMapValues { frames in
        frames.max(by: { $0.width < $1.width }).flatMap { $0.width > 80 ? $0 : nil }
    }
}

func setDelay(_ milliseconds: Int) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
    process.arguments = ["write", "com.jordanbaird.Ice", "MacOS27ClickRestoreDelay", "-int", "\(milliseconds)"]
    try? process.run()
    process.waitUntilExit()
    usleep(1_500_000)
}

let repetitions = CommandLine.arguments.count > 1 ? Int(CommandLine.arguments[1]) ?? 4 : 4
let delays = CommandLine.arguments.count > 2 ? CommandLine.arguments.dropFirst(2).compactMap(Int.init) : [60, 100, 150, 250, 400]

let clocks = clocksByDisplay()
guard !clocks.isEmpty else {
    print("no clock found; is MenuBarAgent running?")
    exit(2)
}
print("clocks: " + clocks.map { "\($0.key) at \(Int($0.value.midX)),\(Int($0.value.midY))" }.joined(separator: "; "))

var failures = 0
for delay in delays {
    setDelay(delay)
    for (display, clockFrame) in clocks.sorted(by: { $0.key < $1.key }) {
        var opened = 0
        var times = [Double]()
        for _ in 0..<repetitions {
            let before = Set(panelWindows().map(\.number))
            let start = Date()
            click(CGPoint(x: clockFrame.midX, y: clockFrame.midY))
            var window: Int?
            while Date().timeIntervalSince(start) < 2.5 {
                if let found = openedPanel(before: before) {
                    window = found
                    break
                }
                usleep(15_000)
            }
            if window != nil {
                opened += 1
                times.append(Date().timeIntervalSince(start) * 1000)
                pressEscape()
            }
            usleep(1_200_000)
        }
        let median = times.isEmpty ? 0 : times.sorted()[times.count / 2]
        let line = String(
            format: "delay %4d ms  display %u: opened %d/%d  median %.0f ms",
            delay, display, opened, repetitions, median
        )
        print(line)
        if opened < repetitions {
            failures += 1
        }
    }
}

// Leave the default unset, so Ice's own measured value decides again.
let clear = Process()
clear.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
clear.arguments = ["delete", "com.jordanbaird.Ice", "MacOS27ClickRestoreDelay"]
try? clear.run()
clear.waitUntilExit()
print(failures == 0 ? "every delay opened the panel every time" : "\(failures) display/delay combinations lost a click")
usleep(250_000)
exit(failures == 0 ? 0 : 1)
