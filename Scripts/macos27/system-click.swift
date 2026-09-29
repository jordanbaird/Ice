// Clicks a MenuBarAgent system item and reports whether its panel opened.
// usage: system-click clock | controlcenter     (exit code 0 when the panel opened)
//
// Whether the panel opened is judged from screenshots of the area under the bar at the
// display's right edge, where both panels appear. Window lists cannot tell: Notification
// Center can keep a full-screen host window on screen with its panel closed (measured).
import AppKit
import ApplicationServices
import ImageIO

func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success ? value : nil
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

/// The share of pixels whose colour changed noticeably between two captures.
func changedShare(_ before: [UInt8], _ after: [UInt8]) -> Double {
    guard !before.isEmpty, before.count == after.count else {
        return 0
    }
    var changed = 0
    for i in stride(from: 0, to: before.count, by: 4) {
        let difference = abs(Int(before[i]) - Int(after[i])) + abs(Int(before[i + 1]) - Int(after[i + 1])) + abs(Int(before[i + 2]) - Int(after[i + 2]))
        if difference > 60 {
            changed += 1
        }
    }
    return Double(changed) / Double(before.count / 4)
}

func click(_ point: CGPoint) {
    let source = CGEventSource(stateID: .hidSystemState)
    let back = CGEvent(source: nil)?.location ?? point
    for type in [CGEventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
        CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
        usleep(60_000)
    }
    CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: back, mouseButton: .left)?.post(tap: .cghidEventTap)
}

let target = CommandLine.arguments[1]
guard let agent = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.MenuBarAgent").first else {
    print("MenuBarAgent is not running")
    exit(2)
}
let application = AXUIElementCreateApplication(agent.processIdentifier)
guard
    let bar = value(application, kAXExtrasMenuBarAttribute),
    let children = value(bar as! AXUIElement, kAXChildrenAttribute) as? [AXUIElement]
else {
    print("no MenuBarAgent items")
    exit(2)
}
// Each system item is a hosting group; its identifier and frame belong to the item inside it.
let systemItems = children.compactMap { (value($0, kAXChildrenAttribute) as? [AXUIElement])?.first }
guard let item = systemItems.first(where: { ((value($0, kAXIdentifierAttribute) as? String) ?? "").hasSuffix(target) }) else {
    print("no \(target) item among \(systemItems.count) system items")
    exit(2)
}
let itemFrame = frame(item)
let itemCenter = CGPoint(x: itemFrame.midX, y: itemFrame.midY)
var displayID = CGDirectDisplayID(0)
var displayCount: UInt32 = 0
CGGetDisplaysWithPoint(itemCenter, 1, &displayID, &displayCount)
let display = CGDisplayBounds(displayID)
let region = CGRect(x: display.maxX - 420, y: itemFrame.maxY + 12, width: 420, height: 480)
let directory = NSTemporaryDirectory()
capture(region, to: directory + "system-click-before.png")
click(itemCenter)
usleep(1_200_000)
capture(region, to: directory + "system-click-after.png")
let share = changedShare(pixels(directory + "system-click-before.png"), pixels(directory + "system-click-after.png"))
let opened = share > 0.15
print("\(target) at \(NSStringFromRect(itemFrame)): \(opened ? "opened" : "did not open") (changed \(String(format: "%.2f", share)) of the panel area)")
if opened {
    if target == "clock" {
        click(itemCenter)
    } else {
        let source = CGEventSource(stateID: .hidSystemState)
        CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: true)?.post(tap: .cghidEventTap)
        CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: false)?.post(tap: .cghidEventTap)
    }
    usleep(800_000)
}
exit(opened ? 0 : 1)
