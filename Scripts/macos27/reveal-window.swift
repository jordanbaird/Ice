// Measures how long the hidden items are actually on show around a bridged click — the flash
// that overlaps the panel's own animation — and so whether the restore delay takes effect.
//
// usage: reveal-window [offset ...] -- [delay ...]     (all in milliseconds)
// Requirements: Ice installed and running and concealing, Thaw not running. Takes the pointer.
import AppKit
import ApplicationServices
import ImageIO

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

func capture(_ region: CGRect, to path: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    process.arguments = ["-x", "-R", "\(Int(region.minX)),\(Int(region.minY)),\(Int(region.width)),\(Int(region.height))", path]
    try? process.run()
    process.waitUntilExit()
}

func pixels(_ path: String) -> [UInt8] {
    guard
        let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else {
        return []
    }
    var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
    let context = CGContext(
        data: &data, width: image.width, height: image.height, bitsPerComponent: 8,
        bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
    context?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return data
}

func changedShare(_ before: [UInt8], _ after: [UInt8]) -> Double {
    guard !before.isEmpty, before.count == after.count else {
        return -1
    }
    var changed = 0
    for i in stride(from: 0, to: before.count, by: 4) {
        let difference = abs(Int(before[i]) - Int(after[i]))
            + abs(Int(before[i + 1]) - Int(after[i + 1]))
            + abs(Int(before[i + 2]) - Int(after[i + 2]))
        if difference > 60 {
            changed += 1
        }
    }
    return Double(changed) / Double(before.count / 4)
}

let source = CGEventSource(stateID: .hidSystemState)

func click(_ point: CGPoint) {
    for type in [CGEventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
        CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?
            .post(tap: .cghidEventTap)
        usleep(20_000)
    }
}

func pressEscape() {
    for down in [true, false] {
        CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: down)?.post(tap: .cghidEventTap)
        usleep(30_000)
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

guard let agent = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.MenuBarAgent").first else {
    print("MenuBarAgent is not running")
    exit(2)
}
let application = AXUIElementCreateApplication(agent.processIdentifier)
var clocksByDisplay = [CGDirectDisplayID: CGRect]()
for window in elements(application, kAXWindowsAttribute) ?? [] {
    for child in elements(window, kAXChildrenAttribute) ?? [] {
        let hosted = elements(child, kAXChildrenAttribute)?.first ?? child
        let itemFrame = frame(hosted)
        guard itemFrame.width > 80 else {
            continue
        }
        var display = CGDirectDisplayID(0)
        var matches: UInt32 = 0
        CGGetDisplaysWithPoint(CGPoint(x: itemFrame.midX, y: itemFrame.midY), 1, &display, &matches)
        guard matches > 0, itemFrame.width > (clocksByDisplay[display]?.width ?? 0) else {
            continue
        }
        clocksByDisplay[display] = itemFrame
    }
}
let sortedClocks = clocksByDisplay.sorted { $0.key < $1.key }
guard let clicked = sortedClocks.first?.value else {
    print("no clock found")
    exit(2)
}
// Notification Center's window covers the whole display it opens on and tints the bar there,
// which would count as a reveal. Lifting concealment moves both displays' bars, so the reveal
// is watched on the other display, where the panel cannot reach.
let watched = sortedClocks.count > 1 ? sortedClocks[1].value : clicked
if sortedClocks.count < 2 {
    print("only one display: the panel's own tint is counted along with the reveal")
}

// The stretch of bar to the left of the system items, where concealed items reappear.
let region = CGRect(x: watched.minX - 760, y: watched.minY - 3, width: 620, height: watched.height + 6)
let directory = NSTemporaryDirectory()

let arguments = CommandLine.arguments.dropFirst()
let separator = arguments.firstIndex(of: "--")
let offsets = separator.map { arguments[arguments.startIndex..<$0].compactMap(Int.init) } ?? [150, 300, 500]
let delays = separator.map { arguments[arguments.index(after: $0)...].compactMap(Int.init) } ?? [60, 400]

capture(region, to: directory + "reveal-concealed.png")
let concealed = pixels(directory + "reveal-concealed.png")
print("bar strip \(NSStringFromRect(region)), concealed baseline taken")

for delay in delays {
    setDelay(delay)
    for offset in offsets {
        let before = pixels(directory + "reveal-concealed.png")
        click(CGPoint(x: clicked.midX, y: clicked.midY))
        usleep(UInt32(offset) * 1000)
        capture(region, to: directory + "reveal-after.png")
        let share = changedShare(before, pixels(directory + "reveal-after.png"))
        print(String(
            format: "delay %4d ms, looked %4d ms after the click: %.2f of the bar strip differs from concealed",
            delay, offset, share
        ))
        pressEscape()
        usleep(1_400_000)
    }
}

// Leave the default unset, so Ice's own measured value decides again.
let clear = Process()
clear.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
clear.arguments = ["delete", "com.jordanbaird.Ice", "MacOS27ClickRestoreDelay"]
try? clear.run()
clear.waitUntilExit()
_ = concealed
usleep(250_000)
