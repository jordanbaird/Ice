// Prints the Ice Bar panel's frame and, for each item image it shows, "item <x> <y> <label>".
// Prints "none" when no Ice Bar is on screen. Read from Ice's Accessibility tree.
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

func images(in element: AXUIElement, depth: Int = 0) -> [(CGRect, String)] {
    guard depth < 14 else {
        return []
    }
    var result = [(CGRect, String)]()
    if
        (value(element, kAXRoleAttribute) as? String) == kAXImageRole,
        let label = value(element, kAXDescriptionAttribute) as? String,
        !label.isEmpty,
        let f = frame(element)
    {
        result.append((f, label))
    }
    for child in value(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
        result += images(in: child, depth: depth + 1)
    }
    return result
}

guard let ice = NSRunningApplication.runningApplications(withBundleIdentifier: "com.jordanbaird.Ice").first else {
    print("none")
    exit(0)
}
let app = AXUIElementCreateApplication(ice.processIdentifier)
AXUIElementSetMessagingTimeout(app, 2)
let panels = (value(app, kAXWindowsAttribute) as? [AXUIElement] ?? []).compactMap { window -> (CGRect, [(CGRect, String)])? in
    guard let f = frame(window), f.height < 90, f.width > 20, f.width < 1400 else {
        return nil
    }
    return (f, images(in: window))
}
guard let panel = panels.first(where: { !$0.1.isEmpty }) ?? panels.first else {
    print("none")
    exit(0)
}
let (panelFrame, items) = panel
print("frame \(Int(panelFrame.midX)) \(Int(panelFrame.midY)) \(Int(panelFrame.width)) \(Int(panelFrame.height))")
for (itemFrame, label) in items {
    print("item \(Int(itemFrame.midX)) \(Int(itemFrame.midY)) \(label)")
}
