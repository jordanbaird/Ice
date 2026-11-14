//
//  source-resolver.swift
//  Ice
//

// Runs the real window-to-app matching from MenuBarItemSourceResolver with
// made-up macOS 26 geometry (every item window owned by Control Center).
// No app launch, Accessibility, or WindowServer access.
import Foundation

let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().path
let source = try String(
    contentsOfFile: repo + "/Ice/MenuBar/MenuBarItems/MenuBarItemSourceResolver.swift",
    encoding: .utf8
)
let start = source.range(of: "    private static func match(")!.lowerBound
let end = source.range(of: "\n}\n", options: .backwards)!.lowerBound
let method = String(source[start..<end]).replacingOccurrences(of: "private static func", with: "static func")

let prelude = #"""
import CoreGraphics
import Foundation
typealias CGWindowID = UInt32
struct WindowInfo {
    let windowID: CGWindowID
    let frame: CGRect
}
enum Resolver {
"""#
let tests = #"""
}
@main struct RegressionTests {
    static var failures = 0
    static func expect(_ value: Bool, _ name: String) {
        print("\(value ? "PASS" : "FAIL"): \(name)")
        if !value { failures += 1 }
    }
    static func window(_ id: CGWindowID, _ x: CGFloat, _ width: CGFloat) -> WindowInfo {
        WindowInfo(windowID: id, frame: CGRect(x: x, y: 0, width: width, height: 33))
    }
    static func item(_ pid: Int32, _ x: CGFloat, _ width: CGFloat) -> (pid: Int32, frame: CGRect) {
        (pid, CGRect(x: x, y: 5, width: width, height: 22))
    }
    static func main() {
        // Three adjacent icons, AX frames a little narrower than the windows.
        let windows = [window(1, 1000, 30), window(2, 1030, 40), window(3, 1070, 30)]
        let items = [item(300, 1072, 26), item(100, 1002, 26), item(200, 1032, 36)]
        let result = Resolver.match(windows: windows, items: items)
        expect(result == [1: 100, 2: 200, 3: 300], "adjacent icons map to their own apps")

        // An item with no window, and a window with no item, stay unmatched.
        let partial = Resolver.match(
            windows: [window(1, 1000, 30), window(9, 500, 30)],
            items: [item(100, 1002, 26), item(400, 2000, 26)]
        )
        expect(partial == [1: 100], "unmatched windows and items are left out")

        // Each item is claimed once: two windows can't share one app item.
        let shared = Resolver.match(
            windows: [window(1, 1000, 30), window(2, 1000, 30)],
            items: [item(100, 1002, 26)]
        )
        expect(shared.count == 1 && shared.values.first == 100, "one item never names two windows")

        // Items hidden off the left edge still match by position.
        let hidden = Resolver.match(
            windows: [window(5, -3000, 30), window(6, -2970, 24)],
            items: [item(600, -2968, 20), item(500, -2998, 26)]
        )
        expect(hidden == [5: 500, 6: 600], "off-screen hidden icons map to their apps")

        // The best-centered item wins a wide window over a nearby edge item.
        let wide = Resolver.match(
            windows: [window(7, 1000, 60)],
            items: [item(700, 1002, 10), item(800, 1020, 20)]
        )
        expect(wide == [7: 800], "closest center wins")

        exit(failures == 0 ? 0 : 1)
    }
}
"""#
let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ice-regression-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
let generated = directory.appendingPathComponent("source-resolver-generated.swift")
try (prelude + "\n" + method + "\n" + tests).write(to: generated, atomically: true, encoding: .utf8)
let compiler = Process()
compiler.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
compiler.arguments = ["swiftc", "-parse-as-library", generated.path, "-o", directory.appendingPathComponent("source-resolver-tests").path]
try compiler.run()
compiler.waitUntilExit()
guard compiler.terminationStatus == 0 else { exit(compiler.terminationStatus) }
let runner = Process()
runner.executableURL = directory.appendingPathComponent("source-resolver-tests")
try runner.run()
runner.waitUntilExit()
let status = runner.terminationStatus
try FileManager.default.removeItem(at: directory)
exit(status)
