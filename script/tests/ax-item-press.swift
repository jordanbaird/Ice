//
//  ax-item-press.swift
//  Ice
//

// Executes production AX discovery/press logic against an in-memory Accessibility tree.
// No UI actions, privacy grants, or running Ice app are needed.
import Foundation

let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().path
var source = try String(contentsOfFile: repo + "/Ice/MenuBar/MenuBarItems/MenuBarItemAXDiscovery.swift", encoding: .utf8)
// Replace only the OS boundary; discovery, item identity, and press selection remain production code.
for name in ["AXUIElement", "NSRunningApplication", "AXIsProcessTrusted", "AXUIElementGetTypeID",
             "AXUIElementCreateApplication", "AXUIElementSetMessagingTimeout",
             "AXUIElementCopyAttributeValue", "AXUIElementPerformAction"] {
    source = source.replacingOccurrences(of: "\\b" + name + "\\b", with: "Fixture" + name, options: .regularExpression)
}
let fixtures = #"""
import Cocoa
import ApplicationServices
final class FixtureAXUIElement: NSObject {
    var attributes: [String: AnyObject]
    var actionResult = AXError.success
    init(_ role: String, title: String? = nil, identifier: String? = nil, children: [FixtureAXUIElement] = []) {
        attributes = [kAXRoleAttribute: role as NSString, kAXChildrenAttribute: children as NSArray]
        attributes[kAXTitleAttribute] = title as NSString?
        attributes["AXIdentifier"] = identifier as NSString?
    }
}
struct FixtureNSRunningApplication {
    let processIdentifier: pid_t = 42
    let localizedName: String? = "Control Center"
    let bundleIdentifier: String? = "com.apple.controlcenter"
    static let current = FixtureNSRunningApplication()
}
var trusted = true
var application = FixtureAXUIElement("AXApplication")
var pressed: [FixtureAXUIElement] = []
func FixtureAXIsProcessTrusted() -> Bool { trusted }
func FixtureAXUIElementGetTypeID() -> CFTypeID { CFGetTypeID(application) }
func FixtureAXUIElementCreateApplication(_ pid: pid_t) -> FixtureAXUIElement { application }
@discardableResult
func FixtureAXUIElementSetMessagingTimeout(_ element: FixtureAXUIElement, _ timeout: Float) -> AXError { .success }
func FixtureAXUIElementCopyAttributeValue(_ element: FixtureAXUIElement, _ attribute: CFString, _ value: UnsafeMutablePointer<AnyObject?>) -> AXError {
    value.pointee = element.attributes[attribute as String]
    return value.pointee == nil ? .noValue : .success
}
func FixtureAXUIElementPerformAction(_ element: FixtureAXUIElement, _ action: CFString) -> AXError {
    precondition(action as String == kAXPressAction)
    pressed.append(element)
    return element.actionResult
}
"""#
let tests = #"""
var failures = 0
func check(_ name: String, title: String? = nil, identifier: String? = nil, changedTitle: Bool = false,
           stale: Bool = false, permission: Bool = true) {
    trusted = true
    pressed = []
    let battery = FixtureAXUIElement("AXMenuBarItem", title: title, identifier: identifier)
    let selected = FixtureAXUIElement("AXMenuBarItem", title: title, identifier: identifier)
    let bar = FixtureAXUIElement("AXMenuBar", children: [battery, selected])
    application.attributes["AXExtrasMenuBar"] = bar
    let items = MenuBarItemAXDiscovery.discoverItems(in: [.current])
    precondition(items.count == 2)
    let item = items[1]
    if changedTitle { selected.attributes[kAXTitleAttribute] = "Updated status" as NSString }
    if stale {
        selected.actionResult = .invalidUIElement
        bar.attributes[kAXChildrenAttribute] = [battery] as NSArray
    }
    trusted = permission
    let succeeded = MenuBarItemAXDiscovery.press(item)
    let expectedTargets = permission ? [selected] : []
    let passed = pressed == expectedTargets && succeeded == (permission && !stale)
    print("\(passed ? "PASS" : "FAIL"): \(name) (pressedBattery=\(pressed.contains(battery)))")
    if !passed { failures += 1 }
}
check("anonymous sibling presses the selected item")
check("duplicate titles preserve selection", title: "Control Center")
check("duplicate identifiers preserve selection", identifier: "com.apple.menuextra.shared")
check("title changes after discovery preserve selection", title: "Status", changedTitle: true)
check("stale selection never falls back to battery", stale: true)
check("denied Accessibility permission performs no action", permission: false)
exit(failures == 0 ? 0 : 1)
"""#
let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ice-ax-regression-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
let generated = directory.appendingPathComponent("ax-test-generated.swift")
try (fixtures + "\n" + source + "\n" + tests).write(to: generated, atomically: true, encoding: .utf8)
let runner = Process()
runner.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
runner.arguments = [generated.path]
try runner.run()
runner.waitUntilExit()
let status = runner.terminationStatus
try FileManager.default.removeItem(at: directory)
exit(status)
