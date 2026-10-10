//
//  ax-row-filter.swift
//  Ice
//

// Exercises the actual AX row scan and shared classifier with controlled discovery geometry.
import Foundation

let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().path
let source = try String(contentsOfFile: repo + "/Ice/UI/IceBar/IceBar.swift", encoding: .utf8)
let discovery = try String(contentsOfFile: repo + "/Ice/MenuBar/MenuBarItems/MenuBarItemAXDiscovery.swift", encoding: .utf8)
func method(_ signature: String, in source: String) -> String {
    let start = source.range(of: signature)!.lowerBound
    let end = source.range(of: "\n    }\n", range: start..<source.endIndex)!.upperBound
    return String(source[start..<end]).replacingOccurrences(of: "private func", with: "func")
}
let scan = method("    private func scanAXRowsOnce(", in: source)
    .replacingOccurrences(of: "NSWorkspace", with: "FixtureWorkspace")
    .replacingOccurrences(of: "NSRunningApplication", with: "FixtureApplication")
let classification = ["    static func classify(", "    static func normalizedDividers(", "    static func isSettledDividerFrame("]
    .map { method($0, in: discovery) }.joined(separator: "\n")
let fixtures = #"""
import Cocoa
struct FixtureApplication {
    init?(processIdentifier: pid_t) {}
    var icon: NSImage? { nil }
}
struct FixtureWorkspace {
    static let shared = FixtureWorkspace()
    let runningApplications = [FixtureApplication]()
}
enum MenuBarItemAXDiscovery {
    enum SectionKind { case visible, hidden, alwaysHidden }
    struct AXMenuBarItem {
        let pid: pid_t = 42
        let bundleID: String? = nil
        let identifier: String? = nil
        let title: String?
        var displayName: String { title ?? "unknown" }
        let axFrame: CGRect?
    }
    static var items = [AXMenuBarItem]()
    static var dividers: (hidden: CGRect?, alwaysHidden: CGRect?) = (nil, nil)
    static func discoverItems(in apps: [FixtureApplication]) -> [AXMenuBarItem] { items }
    static func dividerFrames() -> (hidden: CGRect?, alwaysHidden: CGRect?) { dividers }
    static func systemImageName(forIdentifier id: String?) -> String? { nil }
    static func inputSourceIcon() -> NSImage? { nil }
    // PRODUCTION_CLASSIFICATION
}
struct AXRowItem {
    let id: String
    let item: MenuBarItemAXDiscovery.AXMenuBarItem
    let title: String?
    let displayName: String
    let systemImage: String?
    let appIcon: NSImage?
    let midX: CGFloat?
}
struct Window { let frame: CGRect }
final class ControlItem { var window: Window? }
final class Section {
    enum Name { case hidden, alwaysHidden }
    let controlItem = ControlItem()
}
final class MenuBarManager {
    let hidden = Section()
    let alwaysHidden = Section()
    func section(withName name: Section.Name) -> Section? { name == .hidden ? hidden : alwaysHidden }
}
final class AppState { var isActiveSpaceFullscreen = false }
struct Screen {
    let displayID = 1
    let frame = CGRect(x: 0, y: 0, width: 1200, height: 800)
}
enum MenuBarOverlayPanelContentView {
    static var width: CGFloat?
    static func currentTrailingVisibleWidth(for displayID: Int) -> CGFloat? { width }
}
struct Logger {
    static let iceBar = Logger()
    func info(_ message: String) {}
}
@MainActor final class Content {
    let section = Section.Name.hidden
    let menuBarManager = MenuBarManager()
    let appState = AppState()
    let screen = Screen()
    var axRows = [AXRowItem]()
    // PRODUCTION_SCAN
}
@MainActor func runTests() async {
    var failures = 0
    func expect(_ name: String, _ passed: Bool) {
        print("\(passed ? "PASS" : "FAIL"): \(name)")
        if !passed { failures += 1 }
    }
    func divider(_ x: CGFloat?) -> CGRect? { x.map { CGRect(x: $0, y: 0, width: 20, height: 24) } }
    func check(_ name: String, hidden: CGFloat?, always: CGFloat?, width: CGFloat? = nil,
               fullscreen: Bool = false, nativeHidden: CGFloat? = nil, expected: [String]) async {
        let content = Content()
        content.appState.isActiveSpaceFullscreen = fullscreen
        content.menuBarManager.hidden.controlItem.window = divider(nativeHidden).map { Window(frame: $0) }
        MenuBarItemAXDiscovery.dividers = (divider(hidden), divider(always))
        MenuBarOverlayPanelContentView.width = width
        await content.scanAXRowsOnce(attempt: 0)
        expect(name, content.axRows.compactMap(\.title) == expected)
    }
    MenuBarItemAXDiscovery.items = [1000, 600, 400].map {
        .init(title: String($0), axFrame: CGRect(x: $0 - 10, y: 0, width: 20, height: 24))
    } + [.init(title: "unframed", axFrame: nil)]
    await check("known dividers exclude visible items", hidden: 800, always: 500, expected: ["400", "600"])
    await check("missing always-hidden divider retains hidden items", hidden: 800, always: nil, expected: ["400", "600"])
    await check("missing hidden boundary does not discard unknown items", hidden: nil, always: 500, expected: ["400", "600", "1000", "unframed"])
    await check("partial geometry uses the visible-region fallback", hidden: nil, always: 500, width: 200, expected: ["400", "600"])
    await check("both missing dividers use the visible-region fallback", hidden: nil, always: nil, width: 200, expected: ["400", "600"])
    await check("missing geometry without a visible region retains all items", hidden: nil, always: nil, expected: ["400", "600", "1000", "unframed"])
    await check("fullscreen ignores stale visible-region geometry", hidden: nil, always: 500, width: 200, fullscreen: true, expected: ["400", "600", "1000", "unframed"])
    await check("native hidden-divider fallback retains classification", hidden: nil, always: 500, nativeHidden: 800, expected: ["400", "600"])
    await check("parking-spacer geometry is not a hidden boundary", hidden: 7, always: 500, width: 200, expected: ["400", "600"])
    await check("zero visible width is ignored", hidden: nil, always: 500, width: 0, expected: ["400", "600", "1000", "unframed"])
    await check("oversized visible width is ignored", hidden: nil, always: 500, width: 1400, expected: ["400", "600", "1000", "unframed"])
    expect("shared classifier still treats nil as a disabled section", MenuBarItemAXDiscovery.classify(centerX: 600, hiddenDividerX: nil, alwaysHiddenDividerX: 500) == .visible)
    exit(failures == 0 ? 0 : 1)
}
await runTests()
"""#
let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ice-row-filter-test-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
let generated = directory.appendingPathComponent("row-filter.swift")
try fixtures.replacingOccurrences(of: "    // PRODUCTION_CLASSIFICATION", with: classification)
    .replacingOccurrences(of: "    // PRODUCTION_SCAN", with: scan)
    .write(to: generated, atomically: true, encoding: .utf8)
let runner = Process()
runner.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
runner.arguments = [generated.path]
try runner.run()
runner.waitUntilExit()
let status = runner.terminationStatus
try FileManager.default.removeItem(at: directory)
exit(status)
