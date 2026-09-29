// Lists the menu bar items Accessibility reports on macOS 27, for diagnostics.
// Build: swiftc -O Scripts/macos27/ax-items.swift -o /tmp/ice-ax-items
import AppKit
import ApplicationServices

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

var rows = [(CGFloat, String)]()
for app in NSWorkspace.shared.runningApplications {
    guard let bundleID = app.bundleIdentifier else { continue }
    let application = AXUIElementCreateApplication(app.processIdentifier)
    AXUIElementSetMessagingTimeout(application, 0.5)
    guard
        let bar = value(application, kAXExtrasMenuBarAttribute),
        let children = value(bar as! AXUIElement, kAXChildrenAttribute) as? [AXUIElement]
    else { continue }
    for child in children {
        let f = frame(child)
        let identifier = value(child, kAXIdentifierAttribute) as? String ?? ""
        let subrole = value(child, kAXSubroleAttribute) as? String ?? ""
        let description = value(child, kAXDescriptionAttribute) as? String ?? ""
        let title = value(child, kAXTitleAttribute) as? String ?? ""
        rows.append((f.minX, String(
            format: "%7.0f %5.0f %4.0f  %@  id=%@  subrole=%@  desc=%@  title=%@",
            f.minX, f.minY, f.width, bundleID, identifier, subrole, description, title
        )))
    }
}
for row in rows.sorted(by: { $0.0 < $1.0 }) { print(row.1) }
