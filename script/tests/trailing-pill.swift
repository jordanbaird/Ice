//
//  trailing-pill.swift
//  Ice
//

// Executes the split shape's trailing-pill measurement helpers from the current
// source: the toggle stale-scan rule, the status-frame filter, and the listed
// leading edge over an in-memory Accessibility tree.
// No UI actions, privacy grants, or running Ice app are needed.
import Foundation

let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().path
var discovery = try String(contentsOfFile: repo + "/Ice/MenuBar/MenuBarItems/MenuBarItemAXDiscovery.swift", encoding: .utf8)
let overlay = try String(contentsOfFile: repo + "/Ice/MenuBar/Appearance/MenuBarOverlayPanel.swift", encoding: .utf8)
// Replace only the OS boundary; the item walk stays production code.
for name in ["AXUIElement", "NSRunningApplication", "AXIsProcessTrusted", "AXUIElementGetTypeID",
             "AXUIElementCreateApplication", "AXUIElementSetMessagingTimeout",
             "AXUIElementCopyAttributeValue", "AXUIElementPerformAction"] {
    discovery = discovery.replacingOccurrences(of: "\\b" + name + "\\b", with: "Fixture" + name, options: .regularExpression)
}
func method(_ signature: String, in source: String) -> String {
    let start = source.range(of: signature)!.lowerBound
    let end = source.range(of: "\n    }\n", range: start..<source.endIndex)!.upperBound
    return String(source[start..<end]).replacingOccurrences(of: "private static func", with: "static func")
}
let helpers = [
    "    private static func lagsBehindPrediction(",
    "    private static func isStatusItemFrame(",
    "    private static func listedLeadingEdge(",
].map { method($0, in: overlay) }.joined(separator: "\n")

let fixtures = #"""
import Cocoa
import ApplicationServices
final class FixtureAXUIElement: NSObject {
    var attributes: [String: AnyObject]
    init(_ role: String, frame: CGRect? = nil, children: [FixtureAXUIElement] = []) {
        attributes = [kAXRoleAttribute: role as NSString, kAXChildrenAttribute: children as NSArray]
        if var origin = frame?.origin, var size = frame?.size {
            attributes[kAXPositionAttribute] = AXValueCreate(.cgPoint, &origin)
            attributes[kAXSizeAttribute] = AXValueCreate(.cgSize, &size)
        }
    }
}
struct FixtureNSRunningApplication {
    let processIdentifier: pid_t = 42
    let localizedName: String? = "Fixture"
    let bundleIdentifier: String? = "com.example.fixture"
    static let current = FixtureNSRunningApplication()
}
var trusted = true
var applications = [pid_t: FixtureAXUIElement]()
let emptyApplication = FixtureAXUIElement("AXApplication")
func FixtureAXIsProcessTrusted() -> Bool { trusted }
func FixtureAXUIElementGetTypeID() -> CFTypeID { CFGetTypeID(emptyApplication) }
func FixtureAXUIElementCreateApplication(_ pid: pid_t) -> FixtureAXUIElement { applications[pid] ?? emptyApplication }
@discardableResult
func FixtureAXUIElementSetMessagingTimeout(_ element: FixtureAXUIElement, _ timeout: Float) -> AXError { .success }
func FixtureAXUIElementCopyAttributeValue(_ element: FixtureAXUIElement, _ attribute: CFString, _ value: UnsafeMutablePointer<AnyObject?>) -> AXError {
    value.pointee = element.attributes[attribute as String]
    return value.pointee == nil ? .noValue : .success
}
func FixtureAXUIElementPerformAction(_ element: FixtureAXUIElement, _ action: CFString) -> AXError { .success }
enum Overlay {
    // PRODUCTION_HELPERS
}
"""#

let tests = #"""
var failures = 0
func expect(_ name: String, _ passed: Bool) {
    print("\(passed ? "PASS" : "FAIL"): \(name)")
    if !passed { failures += 1 }
}

// Toggle stale-scan rule. Numbers from a real collapse on macOS 27.2: the pill
// predicted 365pt, the first sweep still saw a hidden icon (402pt), then 365pt.
let collapse = (origin: CGFloat(484), predicted: CGFloat(365))
expect("collapse: a sweep that still sees a hidden icon is held",
       Overlay.lagsBehindPrediction(402, origin: collapse.origin, predicted: collapse.predicted))
expect("collapse: the predicted width lands",
       !Overlay.lagsBehindPrediction(365, origin: collapse.origin, predicted: collapse.predicted))
expect("collapse: pad noise near the prediction lands",
       !Overlay.lagsBehindPrediction(371, origin: collapse.origin, predicted: collapse.predicted))
expect("collapse: narrower than predicted lands at once",
       !Overlay.lagsBehindPrediction(330, origin: collapse.origin, predicted: collapse.predicted))
expect("collapse: the old layout is held",
       Overlay.lagsBehindPrediction(484, origin: collapse.origin, predicted: collapse.predicted))
let reveal = (origin: CGFloat(365), predicted: CGFloat(484))
expect("reveal: the old layout is held",
       Overlay.lagsBehindPrediction(365, origin: reveal.origin, predicted: reveal.predicted))
expect("reveal: a half-revealed layout is held",
       Overlay.lagsBehindPrediction(430, origin: reveal.origin, predicted: reveal.predicted))
expect("reveal: the predicted width lands",
       !Overlay.lagsBehindPrediction(484, origin: reveal.origin, predicted: reveal.predicted))
expect("reveal: wider than predicted lands at once",
       !Overlay.lagsBehindPrediction(520, origin: reveal.origin, predicted: reveal.predicted))

// Status-frame filter on a 1680pt display without a notch.
let display = CGRect(x: 0, y: 0, width: 1680, height: 1050)
expect("an icon is a status frame", Overlay.isStatusItemFrame(CGRect(x: 1487, y: 4, width: 22, height: 22), displayBounds: display))
expect("a wide clock is a status frame", Overlay.isStatusItemFrame(CGRect(x: 1560, y: 4, width: 118, height: 22), displayBounds: display))
expect("a bar-wide glass container is not", !Overlay.isStatusItemFrame(CGRect(x: 0, y: 0, width: 1680, height: 30), displayBounds: display))
expect("half the display is not", !Overlay.isStatusItemFrame(CGRect(x: 840, y: 0, width: 840, height: 30), displayBounds: display))
expect("a tall panel is not", !Overlay.isStatusItemFrame(CGRect(x: 1500, y: 0, width: 300, height: 400), displayBounds: display))
expect("a frame below the bar is not", !Overlay.isStatusItemFrame(CGRect(x: 1500, y: 40, width: 22, height: 22), displayBounds: display))

// Listed leading edge over an in-memory AX tree.
let ownPID = ProcessInfo.processInfo.processIdentifier
func app(_ items: [FixtureAXUIElement]) -> FixtureAXUIElement {
    let application = FixtureAXUIElement("AXApplication")
    application.attributes["AXExtrasMenuBar"] = FixtureAXUIElement("AXMenuBar", children: items)
    return application
}
func item(_ x: CGFloat, _ width: CGFloat = 22, y: CGFloat = 4, children: [FixtureAXUIElement] = []) -> FixtureAXUIElement {
    FixtureAXUIElement("AXMenuBarItem", frame: CGRect(x: x, y: y, width: width, height: 22), children: children)
}
applications = [
    // MenuBarAgent: items wrapped in a group, plus one in overflow (no frame).
    1: app([FixtureAXUIElement("AXGroup", children: [item(1582, 96), item(1540), FixtureAXUIElement("AXMenuBarItem")])]),
    // Third-party item with an open menu under it: the menu is skipped.
    2: app([item(1510, children: [FixtureAXUIElement("AXMenu", children: [FixtureAXUIElement("AXMenuItem", frame: CGRect(x: 900, y: 30, width: 200, height: 22))])])]),
    // An app whose item reports its spot on another display.
    3: app([item(1800)]),
    // An app whose item is parked offscreen.
    4: app([item(1300, y: 986)]),
    // Ice: the expanded spacer is ignored, the Ice icon counts.
    ownPID: app([item(860, 600), item(1487)]),
    // An app the concealer hides: still reports its old frame.
    5: app([item(1200)]),
]
let visiblePIDs: [pid_t] = [1, 2, 3, 4, ownPID]
expect("listing finds the leftmost drawn icon", Overlay.listedLeadingEdge(pids: visiblePIDs, displayBounds: display)?.x == 1487)
expect("listing reports the tallest icon", Overlay.listedLeadingEdge(pids: visiblePIDs, displayBounds: display)?.maxHeight == 22)
expect("listing without Ice still ignores the other display and offscreen items",
       Overlay.listedLeadingEdge(pids: [1, 2, 3, 4], displayBounds: display)?.x == 1510)
expect("a concealed app passed in would widen the pill (callers must leave it out)",
       Overlay.listedLeadingEdge(pids: visiblePIDs + [5], displayBounds: display)?.x == 1200)
expect("no items means no edge", Overlay.listedLeadingEdge(pids: [3, 4], displayBounds: display) == nil)
trusted = false
expect("denied Accessibility permission lists nothing", Overlay.listedLeadingEdge(pids: visiblePIDs, displayBounds: display) == nil)
exit(failures == 0 ? 0 : 1)
"""#

let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ice-trailing-pill-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
let generated = directory.appendingPathComponent("trailing-pill-generated.swift")
let program = fixtures.replacingOccurrences(of: "    // PRODUCTION_HELPERS", with: helpers)
    + "\n" + discovery + "\n" + tests
try program.write(to: generated, atomically: true, encoding: .utf8)
let runner = Process()
runner.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
runner.arguments = [generated.path]
try runner.run()
runner.waitUntilExit()
let status = runner.terminationStatus
try FileManager.default.removeItem(at: directory)
exit(status)
