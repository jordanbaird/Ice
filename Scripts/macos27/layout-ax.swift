// Reads Ice's settings window: "sidebar <x> <y>" for the Menu Bar Layout entry, and
// "image <row> <x> <y> <label>" for each layout item, rows 0 Visible, 1 Hidden, 2 Always Hidden.
import AppKit
import ApplicationServices

func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success ? value : nil
}

func frame(_ element: AXUIElement) -> CGRect? {
    guard let p = value(element, kAXPositionAttribute), let s = value(element, kAXSizeAttribute) else {
        return nil
    }
    var point = CGPoint.zero
    var size = CGSize.zero
    AXValueGetValue(p as! AXValue, .cgPoint, &point)
    AXValueGetValue(s as! AXValue, .cgSize, &size)
    return CGRect(origin: point, size: size)
}

var sidebar: CGRect?
var images = [(CGRect, String)]()
func walk(_ element: AXUIElement, depth: Int) {
    guard depth < 30 else {
        return
    }
    let role = value(element, kAXRoleAttribute) as? String
    let text = (value(element, kAXValueAttribute) as? String) ?? (value(element, kAXTitleAttribute) as? String) ?? ""
    if sidebar == nil, role == kAXStaticTextRole, text == "Menu Bar Layout", let f = frame(element) {
        sidebar = f
    }
    if role == kAXImageRole, let label = value(element, kAXDescriptionAttribute) as? String, !label.isEmpty, let f = frame(element), f.width < 80 {
        images.append((f, label))
    }
    for child in value(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
        walk(child, depth: depth + 1)
    }
}

guard let ice = NSRunningApplication.runningApplications(withBundleIdentifier: "com.jordanbaird.Ice").first else {
    exit(1)
}
let app = AXUIElementCreateApplication(ice.processIdentifier)
AXUIElementSetMessagingTimeout(app, 3)
for window in value(app, kAXWindowsAttribute) as? [AXUIElement] ?? [] {
    guard let f = frame(window), f.height > 300 else {
        continue
    }
    walk(window, depth: 0)
}
if let sidebar {
    print("sidebar \(Int(sidebar.midX)) \(Int(sidebar.midY))")
}
var rows = [CGFloat]()
for (f, _) in images.sorted(by: { $0.0.midY < $1.0.midY }) where !rows.contains(where: { abs($0 - f.midY) < 12 }) {
    rows.append(f.midY)
}
for (f, label) in images {
    let row = rows.firstIndex { abs($0 - f.midY) < 12 } ?? -1
    print("image \(row) \(Int(f.midX)) \(Int(f.midY)) \(label)")
}
