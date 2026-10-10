//
//  ax-activation.swift
//  Ice
//

// Exercises the actual Ice Bar click handler and activation lifecycle with a controlled menu server.
import Foundation

let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().path
let source = try String(contentsOfFile: repo + "/Ice/UI/IceBar/IceBar.swift", encoding: .utf8)
let rowStart = source.range(of: "    private func press(_ row: AXRowItem)")!.lowerBound
let rowEnd = source.range(of: "\n}\n\n// MARK: - IceBarItemView", range: rowStart..<source.endIndex)!.lowerBound
let rowMethod = String(source[rowStart..<rowEnd]).replacingOccurrences(of: "private func", with: "func")
let activationStart = source.range(of: "    func activateAXItem(")!.lowerBound
let activationEnd = source.range(of: "\n    }\n", range: activationStart..<source.endIndex)!.upperBound
let activationMethod = String(source[activationStart..<activationEnd])
let sectionSource = try String(contentsOfFile: repo + "/Ice/MenuBar/MenuBarSection.swift", encoding: .utf8)
let hideStart = sectionSource.range(of: "    func hide(persistState:")!.lowerBound
let hideEnd = sectionSource.range(of: "\n    }\n", range: hideStart..<sectionSource.endIndex)!.upperBound
let hideMethod = "    @MainActor\n" + String(sectionSource[hideStart..<hideEnd])
func sectionMethod(_ signature: String) -> String {
    let start = sectionSource.range(of: signature)!.lowerBound
    let end = sectionSource.range(of: "\n    }\n", range: start..<sectionSource.endIndex)!.upperBound
    return "    @MainActor\n" + String(sectionSource[start..<end])
        .replacingOccurrences(of: "private func", with: "func")
        .replacingOccurrences(of: "NSScreen", with: "TestScreen")
        .replacingOccurrences(of: "NSEvent", with: "TestEvent")
}
let startRehideMethod = sectionMethod("    func startRehideChecks()")
let stopRehideMethod = sectionMethod("    private func stopRehideChecks()")
let fixtures = #"""
import Cocoa
final class TestScreen {
    static let main: TestScreen? = TestScreen()
    let visibleFrame = CGRect(x: 0, y: 0, width: 1200, height: 700)
}
enum TestEvent { static let mouseLocation = CGPoint(x: 100, y: 100) }
final class TestTimer {
    var isValid = true
    let handler: @Sendable (TestTimer) -> Void
    init(handler: @escaping @Sendable (TestTimer) -> Void) { self.handler = handler }
    static func scheduledTimer(withTimeInterval: TimeInterval, repeats: Bool, block: @escaping @Sendable (TestTimer) -> Void) -> TestTimer { TestTimer(handler: block) }
    func invalidate() { isValid = false }
    func fire() { isValid = false; handler(self) }
}
final class UniversalEventMonitor {
    enum Mask { case mouseMoved }
    let handler: (Int) -> Int
    var isRunning = false
    init(mask: Mask, handler: @escaping (Int) -> Int) { self.handler = handler }
    func start() { isRunning = true }
    func stop() { isRunning = false }
}
final class GeneralSettings {
    enum Strategy { case timed }
    let autoRehide = true
    let rehideStrategy = Strategy.timed
    let rehideInterval: TimeInterval = 3
}
final class SettingsManager { let generalSettingsManager = GeneralSettings() }
final class ControlItem {
    enum HidingState { case hideItems, showItems }
    var state = HidingState.hideItems
}
final class MenuBarSection {
    enum Name: CaseIterable { case visible, hidden, alwaysHidden }
    let name: Name
    init(name: Name) { self.name = name }
    weak var appState: AppState?
    var iceBarPanel: IceBarPanel? { appState?.menuBarManager.iceBarPanel }
    var useIceBar = true
    let controlItem = ControlItem()
    var stateRevision = 0
    var isEnabled = true
    var persistedWrites = 0
    var rehideTimer: TestTimer?
    var rehideMonitor: UniversalEventMonitor?
    var isHidden: Bool { controlItem.state == .hideItems }
    func setState(_ state: ControlItem.HidingState, persist: Bool) {
        controlItem.state = state
        stateRevision += 1
        if persist { persistedWrites += 1 }
    }
    // PRODUCTION_HIDE_METHOD
    // PRODUCTION_START_REHIDE
    // PRODUCTION_STOP_REHIDE
}
final class MenuBarManager {
    let sections = MenuBarSection.Name.allCases.map { MenuBarSection(name: $0) }
    var iceBarPanel: IceBarPanel!
    func section(withName name: MenuBarSection.Name) -> MenuBarSection? { sections.first { $0.name == name } }
}
final class AppState {
    let menuBarManager = MenuBarManager()
    let settingsManager = SettingsManager()
    func allowShowOnHover() {}
}
struct Logger {
    static let iceBar = Logger()
    static let controlItem = Logger()
    func info(_ message: String) {}
    func error(_ message: String) {}
}
final class MenuServer: @unchecked Sendable {
    let lock = NSLock()
    var sections = [MenuBarSection]()
    var presses = [Bool]()
    var succeeds = true
    var opensMenu = true
    var menuUntil = Date.distantPast
    var menuDuration: TimeInterval = 0.65
    var menuHeight: CGFloat = 220
    var opensSubmenu = false
    var submenuUntil = Date.distantPast
    func press() -> Bool {
        lock.lock(); defer { lock.unlock() }
        let visible = sections.filter(\.isEnabled).allSatisfy { $0.controlItem.state == .showItems }
        presses.append(visible)
        if visible && succeeds && opensMenu {
            menuUntil = Date().addingTimeInterval(menuDuration)
            if opensSubmenu { submenuUntil = Date().addingTimeInterval(0.3) }
        }
        return succeeds
    }
    var menuIsOpen: Bool {
        lock.lock(); defer { lock.unlock() }
        return Date() < menuUntil
    }
}
let server = MenuServer()
enum MenuBarItemAXDiscovery {
    struct AXMenuBarItem {
        let element = NSObject()
        let pid: pid_t = 42
        let identifier: String? = nil
        let title: String? = nil
    }
    static func press(_ item: AXMenuBarItem) -> Bool { server.press() }
}
struct WindowInfo {
    let windowID: CGWindowID
    let ownerPID: pid_t = 42
    let layer = Int(CGWindowLevelForKey(.popUpMenuWindow))
    var frame: CGRect { CGRect(x: 900, y: 24, width: 180, height: server.menuHeight) }
    var isMenuBarItem: Bool { layer == kCGStatusWindowLevel }
    var isOnScreen: Bool { windowID == 100 ? Date() < server.submenuUntil : server.menuIsOpen }
    init?(windowID: CGWindowID) {
        guard windowID == 99 || windowID == 100 else { return nil }
        self.windowID = windowID
    }
    static func getOnScreenWindows() -> [WindowInfo] {
        [WindowInfo(windowID: 100)!, WindowInfo(windowID: 99)!].filter(\.isOnScreen)
    }
}
@MainActor final class IceBarPanel {
    var appState: AppState?
    var axActivationTask: Task<Void, Never>?
    var isActivatingAXItem = false
    var closed = false
    func close() { closed = true }
"""#
let middle = #"""
}
struct AXRowItem { let item = MenuBarItemAXDiscovery.AXMenuBarItem() }
@MainActor final class Content {
    let menuBarManager: MenuBarManager
    init(_ manager: MenuBarManager) { menuBarManager = manager }
    func closePanel() { menuBarManager.iceBarPanel.close() }
"""#
let tests = #"""
}
@MainActor func runTests() async {
    var failures = 0
    func expect(_ name: String, _ condition: Bool) {
        print("\(condition ? "PASS" : "FAIL"): \(name)")
        if !condition { failures += 1 }
    }
    func setup() -> (AppState, IceBarPanel, Content) {
        let app = AppState()
        let panel = IceBarPanel()
        panel.appState = app
        app.menuBarManager.iceBarPanel = panel
        for section in app.menuBarManager.sections { section.appState = app }
        server.sections = app.menuBarManager.sections
        server.presses = []
        server.succeeds = true
        server.opensMenu = true
        server.menuUntil = .distantPast
        server.menuDuration = 0.65
        server.menuHeight = 220
        server.opensSubmenu = false
        server.submenuUntil = .distantPast
        return (app, panel, Content(app.menuBarManager))
    }
    let (app, panel, content) = setup()
    app.menuBarManager.sections[0].setState(.showItems, persist: false)
    content.press(AXRowItem())
    try? await Task.sleep(for: .milliseconds(450))
    expect("original items are visible before AXPress", server.presses == [true])
    expect("the opened menu stays visible", server.menuIsOpen)
    expect("the Ice Bar closes before activation", panel.closed)
    if let task = panel.axActivationTask { await task.value }
    expect("previously hidden section is restored", app.menuBarManager.sections[1].controlItem.state == .hideItems)
    expect("previously visible section stays visible", app.menuBarManager.sections[0].controlItem.state == .showItems)
    expect("temporary reveal never persists settings", app.menuBarManager.sections.allSatisfy { $0.persistedWrites == 0 })
    expect("previously visible sections resume automatic rehide checks", app.menuBarManager.sections[0].rehideMonitor?.isRunning == true)

    let (rehideApp, rehidePanel, rehideContent) = setup()
    let timedSection = rehideApp.menuBarManager.sections[0]
    timedSection.setState(.showItems, persist: false)
    timedSection.startRehideChecks()
    _ = timedSection.rehideMonitor?.handler(0)
    let firedTimer = timedSection.rehideTimer
    rehideContent.press(AXRowItem())
    try? await Task.sleep(for: .milliseconds(450))
    firedTimer?.fire()
    try? await Task.sleep(for: .milliseconds(50))
    expect("automatic rehide cannot hide originals while a popup is open", rehideApp.menuBarManager.sections.allSatisfy { $0.controlItem.state == .showItems })
    if let task = rehidePanel.axActivationTask { await task.value }
    _ = timedSection.rehideMonitor?.handler(0)
    expect("a fired timer does not prevent scheduling the next automatic rehide", timedSection.rehideTimer !== firedTimer && timedSection.rehideTimer?.isValid == true)
    for section in rehideApp.menuBarManager.sections { section.setState(.showItems, persist: false) }
    rehideApp.menuBarManager.sections[1].hide(persistState: false)
    expect("automatic rehide is enabled again after activation", rehideApp.menuBarManager.sections.allSatisfy { $0.controlItem.state == .hideItems })

    let (manualApp, manualPanel, manualContent) = setup()
    manualContent.press(AXRowItem())
    try? await Task.sleep(for: .milliseconds(450))
    manualApp.menuBarManager.sections[1].hide()
    expect("explicit user hide is not blocked by activation", manualApp.menuBarManager.sections.allSatisfy { $0.controlItem.state == .hideItems && $0.persistedWrites == 1 })
    if let task = manualPanel.axActivationTask { await task.value }

    let (failedApp, failedPanel, failedContent) = setup()
    server.succeeds = false
    failedContent.press(AXRowItem())
    try? await Task.sleep(for: .milliseconds(450))
    if let task = failedPanel.axActivationTask { await task.value }
    expect("failed press restores hidden items", server.presses == [true] && failedApp.menuBarManager.sections.allSatisfy { $0.controlItem.state == .hideItems })

    let (changedApp, changedPanel, changedContent) = setup()
    changedContent.press(AXRowItem())
    try? await Task.sleep(for: .milliseconds(450))
    changedApp.menuBarManager.sections[1].setState(.showItems, persist: true)
    if let task = changedPanel.axActivationTask { await task.value }
    expect("cleanup preserves a newer user choice", changedApp.menuBarManager.sections[1].controlItem.state == .showItems)

    let (submenuApp, submenuPanel, submenuContent) = setup()
    server.opensSubmenu = true
    server.menuDuration = 1.2
    submenuContent.press(AXRowItem())
    try? await Task.sleep(for: .milliseconds(850))
    expect("closing a submenu keeps originals visible while its parent is open", submenuApp.menuBarManager.sections.allSatisfy { $0.controlItem.state == .showItems })
    if let task = submenuPanel.axActivationTask { await task.value }

    let (compactApp, compactPanel, compactContent) = setup()
    server.menuHeight = 32
    server.menuDuration = 1.8
    compactContent.press(AXRowItem())
    try? await Task.sleep(for: .milliseconds(1550))
    expect("compact popups keep originals visible until dismissal", compactApp.menuBarManager.sections.allSatisfy { $0.controlItem.state == .showItems })
    if let task = compactPanel.axActivationTask { await task.value }

    let (noMenuApp, noMenuPanel, noMenuContent) = setup()
    server.opensMenu = false
    noMenuContent.press(AXRowItem())
    try? await Task.sleep(for: .milliseconds(450))
    if let task = noMenuPanel.axActivationTask { await task.value }
    expect("acknowledged no-op restores items without a second click", server.presses == [true] && noMenuApp.menuBarManager.sections.allSatisfy { $0.controlItem.state == .hideItems })

    let (cancelledApp, cancelledPanel, cancelledContent) = setup()
    cancelledContent.press(AXRowItem())
    try? await Task.sleep(for: .milliseconds(50))
    cancelledPanel.axActivationTask?.cancel()
    if let task = cancelledPanel.axActivationTask { await task.value }
    try? await Task.sleep(for: .milliseconds(100))
    expect("cancellation restores items without pressing", server.presses.isEmpty && cancelledApp.menuBarManager.sections.allSatisfy { $0.controlItem.state == .hideItems })
    exit(failures == 0 ? 0 : 1)
}
await runTests()
"""#
let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ice-activation-test-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
let generated = directory.appendingPathComponent("activation.swift")
let productionFixtures = fixtures
    .replacingOccurrences(of: "    // PRODUCTION_HIDE_METHOD", with: hideMethod)
    .replacingOccurrences(of: "    // PRODUCTION_START_REHIDE", with: startRehideMethod)
    .replacingOccurrences(of: "    // PRODUCTION_STOP_REHIDE", with: stopRehideMethod)
try (productionFixtures + "\n" + activationMethod + "\n" + middle + "\n" + rowMethod + "\n" + tests)
    .write(to: generated, atomically: true, encoding: .utf8)
let runner = Process()
runner.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
runner.arguments = [generated.path]
try runner.run()
runner.waitUntilExit()
let status = runner.terminationStatus
try FileManager.default.removeItem(at: directory)
exit(status)
