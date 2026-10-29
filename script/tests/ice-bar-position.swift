//
//  ice-bar-position.swift
//  Ice
//

// Exercises the actual Ice Bar positioning method with controlled screen/window geometry.
// This does not launch the app or change the user's settings.
import Foundation

let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().path
let source = try String(contentsOfFile: repo + "/Ice/UI/IceBar/IceBar.swift", encoding: .utf8)
let start = source.range(of: "    private func updateOrigin(for screen:")!.lowerBound
let end = source.range(of: "\n    }\n", range: start..<source.endIndex)!.upperBound
let method = String(source[start..<end]).replacingOccurrences(of: "private func", with: "func")
let prelude = #"""
import Foundation
import CoreGraphics
enum IceBarLocation { case dynamic, mousePointer, iceIcon }
struct NSScreen {
    var frame = CGRect(x: 0, y: 0, width: 1440, height: 900)
    func getMenuBarHeight() -> CGFloat? { 24 }
}
extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
enum MouseCursor { static var locationAppKit: CGPoint? = CGPoint(x: 720, y: 900) }
enum Bridging {
    static var itemFrame: CGRect?
    static func getWindowFrame(for windowID: UInt32) -> CGRect? { itemFrame }
}
struct ControlItem {
    var windowID: UInt32?
    var windowFrame: CGRect?
}
struct Section { var controlItem = ControlItem() }
struct MenuBarManager {
    enum Name { case visible }
    var section = Section()
    func section(withName: Name) -> Section? { section }
}
struct EventManager { var isMouseInsideEmptyMenuBarSpace = false }
struct GeneralSettings { var iceBarLocation = IceBarLocation.iceIcon }
struct Settings { var generalSettingsManager = GeneralSettings() }
struct AppState {
    var eventManager = EventManager()
    var menuBarManager = MenuBarManager()
    var settingsManager = Settings()
}
class Panel {
    var appState: AppState? = AppState()
    var frame = CGRect(x: 0, y: 0, width: 200, height: 30)
    func setFrameOrigin(_ point: CGPoint) { frame.origin = point }
"""#
let tests = #"""
}
var failures = 0
func check(_ name: String, windowID: UInt32?, serverFrame: CGRect?, localFrame: CGRect?, screen: NSScreen = NSScreen(), expectedX: CGFloat) {
    let panel = Panel()
    panel.appState?.menuBarManager.section.controlItem = ControlItem(windowID: windowID, windowFrame: localFrame)
    Bridging.itemFrame = serverFrame
    panel.updateOrigin(for: screen)
    let passed = panel.frame.minX == expectedX
    print("\(passed ? "PASS" : "FAIL"): \(name) (x=\(panel.frame.minX))")
    if !passed { failures += 1 }
}
let icon = CGRect(x: 1000, y: 0, width: 24, height: 24)
check("anchor without a CGS window ID", windowID: nil, serverFrame: nil, localFrame: icon, expectedX: 912)
check("anchor after CGS frame lookup failure", windowID: 12, serverFrame: nil, localFrame: icon, expectedX: 912)
check("prefer a valid CGS frame", windowID: 12, serverFrame: icon,
      localFrame: CGRect(x: 200, y: 876, width: 24, height: 24), expectedX: 912)
check("retain right-edge fallback without any geometry", windowID: nil, serverFrame: nil, localFrame: nil, expectedX: 1240)
check("clamp the bar at the screen edge", windowID: nil, serverFrame: nil,
      localFrame: CGRect(x: 1420, y: 876, width: 20, height: 24), expectedX: 1240)
check("anchor on a display left of the main screen", windowID: nil, serverFrame: nil,
      localFrame: CGRect(x: -400, y: 876, width: 24, height: 24),
      screen: NSScreen(frame: CGRect(x: -1440, y: 0, width: 1440, height: 900)), expectedX: -488)
exit(failures == 0 ? 0 : 1)
"""#
let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ice-regression-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
let generated = directory.appendingPathComponent("position-test-generated.swift")
try (prelude + "\n" + method + "\n" + tests).write(to: generated, atomically: true, encoding: .utf8)
let runner = Process()
runner.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
runner.arguments = [generated.path]
try runner.run()
runner.waitUntilExit()
let status = runner.terminationStatus
try FileManager.default.removeItem(at: directory)
exit(status)
