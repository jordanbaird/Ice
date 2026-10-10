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
let eventSource = try String(contentsOfFile: repo + "/Ice/Events/EventManager.swift", encoding: .utf8)
func eventMethod(_ signature: String) -> String {
    let start = eventSource.range(of: signature)!.lowerBound
    let end = eventSource.range(of: "\n    }\n", range: start..<eventSource.endIndex)!.upperBound
    return String(eventSource[start..<end])
        .replacingOccurrences(of: "private func", with: "func")
        .replacingOccurrences(of: "NSEvent", with: "ScrollEvent")
}
let hoverMethod = eventMethod("    private func handleShowOnHover()")
let scrollMethod = eventMethod("    private func handleShowOnScroll(")
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
    let showOnHover = true
    let showOnScroll = true
}
final class AdvancedSettings { let showOnHoverDelay: TimeInterval = 0 }
final class SettingsManager {
    let generalSettingsManager = GeneralSettings()
    let advancedSettingsManager = AdvancedSettings()
}
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
    var onStateChange: (() -> Void)?
    var rehideTimer: TestTimer?
    var rehideMonitor: UniversalEventMonitor?
    var isHidden: Bool { controlItem.state == .hideItems }
    func show() { setState(.showItems, persist: true) }
    func setState(_ state: ControlItem.HidingState, persist: Bool) {
        controlItem.state = state
        stateRevision += 1
        if persist { persistedWrites += 1 }
        server.update {
            $0.visibility[name] = state == .showItems
            if state == .hideItems && $0.menuOpen { $0.hidesWhileOpen += 1 }
        }
        onStateChange?()
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
    let isShowOnHoverPrevented = false
    func allowShowOnHover() {}
}
struct ScrollEvent { let scrollingDeltaX: CGFloat; let scrollingDeltaY: CGFloat }
@MainActor final class EventManager {
    var appState: AppState?
    var lastHoverCheck = Date.distantPast
    var lastScrollCheck = Date.distantPast
    static let hoverThrottleInterval: TimeInterval = 0.05
    static let scrollThrottleInterval: TimeInterval = 0.05
    var isMouseInsideEmptyMenuBarSpace = false
    var isMouseInsideMenuBar = false
    var mouseInsideIceBar = false
    var outsideChecks = 0
    var isMouseInsideIceBar: Bool { outsideChecks += 1; return mouseInsideIceBar }
    // PRODUCTION_HOVER
    // PRODUCTION_SCROLL
}
struct Logger {
    static let iceBar = Logger()
    static let controlItem = Logger()
    func info(_ message: String) {}
    func error(_ message: String) {}
}
final class MenuServer: @unchecked Sendable {
    struct State {
        var visibility = Dictionary(uniqueKeysWithValues: MenuBarSection.Name.allCases.map { ($0, false) })
        var presses = [Int]()
        var visibleAtPress = [Bool]()
        var succeeds = true
        var opensMenu = true
        var pausePress = false
        var menuOpen = false
        var menuHeight: CGFloat = 220
        var opensSubmenu = false
        var submenuOpen = false
        var menuReads = 0
        var hidesWhileOpen = 0
    }
    private let condition = NSCondition()
    private var state = State()
    var snapshot: State {
        condition.lock(); defer { condition.unlock() }
        return state
    }
    func update(_ body: (inout State) -> Void) {
        condition.lock(); defer { condition.unlock() }
        body(&state)
        condition.broadcast()
    }
    func press(_ id: Int) -> Bool {
        condition.lock(); defer { condition.unlock() }
        let visible = state.visibility.values.allSatisfy { $0 }
        state.presses.append(id)
        state.visibleAtPress.append(visible)
        // Model an AX request that is still in flight when another item is selected.
        while state.pausePress { condition.wait() }
        if visible && state.succeeds && state.opensMenu {
            state.menuOpen = true
            state.submenuOpen = state.opensSubmenu
        }
        return state.succeeds
    }
    func windows() -> [WindowInfo] {
        condition.lock(); defer { condition.unlock() }
        guard state.menuOpen else { return [] }
        state.menuReads += 1
        let ids: [CGWindowID] = state.submenuOpen ? [100, 99] : [99]
        return ids.map { WindowInfo(windowID: $0, height: state.menuHeight) }
    }
}
let server = MenuServer()
enum MenuBarItemAXDiscovery {
    struct AXMenuBarItem {
        var testID = 1
        let element = NSObject()
        let pid: pid_t = 42
        let identifier: String? = nil
        let title: String? = nil
    }
    static func press(_ item: AXMenuBarItem) -> Bool { server.press(item.testID) }
}
struct WindowInfo {
    let windowID: CGWindowID
    let ownerPID: pid_t = 42
    let layer = Int(CGWindowLevelForKey(.popUpMenuWindow))
    let height: CGFloat
    var frame: CGRect { CGRect(x: 900, y: 24, width: 180, height: height) }
    var isMenuBarItem: Bool { layer == kCGStatusWindowLevel }
    static func getOnScreenWindows() -> [WindowInfo] { server.windows() }
}
@MainActor final class IceBarPanel {
    var appState: AppState?
    var axActivationTask: Task<Void, Never>?
    private var activating = false
    var activationReads = 0
    var isActivatingAXItem: Bool {
        get { activationReads += 1; return activating }
        set { activating = newValue }
    }
    var closed = false
    func close() { closed = true }
"""#
let middle = #"""
}
struct AXRowItem { var item = MenuBarItemAXDiscovery.AXMenuBarItem() }
@MainActor final class Content {
    let menuBarManager: MenuBarManager
    init(_ manager: MenuBarManager) { menuBarManager = manager }
    func closePanel() { menuBarManager.iceBarPanel.close() }
"""#
let tests = #"""
}
@MainActor final class Completion { var done = false }
@MainActor func completion(of task: Task<Void, Never>?) -> Completion {
    let result = Completion()
    Task { await task?.value; result.done = true }
    return result
}
@MainActor func until(_ name: String, _ predicate: () -> Bool) async {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while !predicate() {
        guard ContinuousClock.now < deadline else {
            print("FAIL: timed out waiting for \(name)")
            exit(1)
        }
        try? await Task.sleep(for: .milliseconds(10))
    }
}
@MainActor func menuObserved() async {
    await until("popup observation") { server.snapshot.menuReads >= 2 }
}
@MainActor func finish(_ panel: IceBarPanel) async {
    server.update { $0.menuOpen = false; $0.submenuOpen = false }
    let result = completion(of: panel.axActivationTask)
    await until("activation cleanup") { result.done }
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
        server.update { $0 = MenuServer.State() }
        return (app, panel, Content(app.menuBarManager))
    }
    let (app, panel, content) = setup()
    app.menuBarManager.sections[0].setState(.showItems, persist: false)
    content.press(AXRowItem())
    await menuObserved()
    expect("original items are visible before AXPress", server.snapshot.visibleAtPress == [true])
    expect("the opened menu stays visible", server.snapshot.menuOpen)
    expect("the Ice Bar closes before activation", panel.closed)
    await finish(panel)
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
    await menuObserved()
    let guardReads = rehidePanel.activationReads
    firedTimer?.fire()
    await until("automatic hide guard") { rehidePanel.activationReads > guardReads }
    expect("automatic rehide cannot hide originals while a popup is open", rehideApp.menuBarManager.sections.allSatisfy { $0.controlItem.state == .showItems })
    await finish(rehidePanel)
    _ = timedSection.rehideMonitor?.handler(0)
    expect("a fired timer does not prevent scheduling the next automatic rehide", timedSection.rehideTimer !== firedTimer && timedSection.rehideTimer?.isValid == true)
    for section in rehideApp.menuBarManager.sections { section.setState(.showItems, persist: false) }
    rehideApp.menuBarManager.sections[1].hide(persistState: false)
    expect("automatic rehide is enabled again after activation", rehideApp.menuBarManager.sections.allSatisfy { $0.controlItem.state == .hideItems })

    let (manualApp, manualPanel, manualContent) = setup()
    manualContent.press(AXRowItem())
    await menuObserved()
    manualApp.menuBarManager.sections[1].hide()
    expect("explicit user hide is not blocked by activation", manualApp.menuBarManager.sections.allSatisfy { $0.controlItem.state == .hideItems && $0.persistedWrites == 1 })
    await finish(manualPanel)

    let (failedApp, failedPanel, failedContent) = setup()
    server.update { $0.succeeds = false }
    failedContent.press(AXRowItem())
    await finish(failedPanel)
    expect("failed press restores hidden items", server.snapshot.visibleAtPress == [true] && failedApp.menuBarManager.sections.allSatisfy { $0.controlItem.state == .hideItems })

    let (changedApp, changedPanel, changedContent) = setup()
    changedContent.press(AXRowItem())
    await menuObserved()
    changedApp.menuBarManager.sections[1].setState(.showItems, persist: true)
    await finish(changedPanel)
    expect("cleanup preserves a newer user choice", changedApp.menuBarManager.sections[1].controlItem.state == .showItems)

    let (submenuApp, submenuPanel, submenuContent) = setup()
    server.update { $0.opensSubmenu = true }
    submenuContent.press(AXRowItem())
    await menuObserved()
    let submenuReads = server.snapshot.menuReads
    let submenuCompletion = completion(of: submenuPanel.axActivationTask)
    server.update { $0.submenuOpen = false }
    await until("parent popup observation after submenu closes") { server.snapshot.menuReads > submenuReads || submenuCompletion.done }
    expect("closing a submenu keeps originals visible while its parent is open", !submenuCompletion.done && submenuApp.menuBarManager.sections.allSatisfy { $0.controlItem.state == .showItems })
    await finish(submenuPanel)

    let (compactApp, compactPanel, compactContent) = setup()
    server.update { $0.menuHeight = 32 }
    compactContent.press(AXRowItem())
    let compactCompletion = completion(of: compactPanel.axActivationTask)
    // A rejected popup can still be enumerated by all ten initial detection attempts.
    // Require observation beyond that phase, or report early cleanup as a failure.
    await until("compact popup lifetime observation") { server.snapshot.menuReads > 10 || compactCompletion.done }
    expect("compact popups keep originals visible until dismissal", !compactCompletion.done && compactApp.menuBarManager.sections.allSatisfy { $0.controlItem.state == .showItems })
    await finish(compactPanel)

    let (noMenuApp, noMenuPanel, noMenuContent) = setup()
    server.update { $0.opensMenu = false }
    noMenuContent.press(AXRowItem())
    await finish(noMenuPanel)
    expect("acknowledged no-op restores items without a second click", server.snapshot.visibleAtPress == [true] && noMenuApp.menuBarManager.sections.allSatisfy { $0.controlItem.state == .hideItems })

    let (cancelledApp, cancelledPanel, cancelledContent) = setup()
    // Cancel at the reveal boundary, not within a wall-clock race against the 250ms settle.
    cancelledApp.menuBarManager.sections[0].onStateChange = {
        cancelledPanel.axActivationTask?.cancel()
    }
    cancelledContent.press(AXRowItem())
    await finish(cancelledPanel)
    expect("cancellation restores items without pressing", server.snapshot.presses.isEmpty && cancelledApp.menuBarManager.sections.allSatisfy { $0.controlItem.state == .hideItems })

    let (hoverApp, hoverPanel, hoverContent) = setup()
    hoverContent.press(AXRowItem())
    await menuObserved()
    let hover = EventManager()
    hover.appState = hoverApp
    hover.handleShowOnHover()
    await until("hover exit recheck") { hover.outsideChecks >= 2 }
    expect("hover exit cannot hide or persist while a popup is open", hoverApp.menuBarManager.sections.allSatisfy { $0.controlItem.state == .showItems && $0.persistedWrites == 0 })
    await finish(hoverPanel)

    let (idleApp, _, _) = setup()
    for section in idleApp.menuBarManager.sections { section.setState(.showItems, persist: false) }
    let idleHover = EventManager()
    idleHover.appState = idleApp
    idleHover.handleShowOnHover()
    await until("idle hover recheck") { idleHover.outsideChecks >= 2 }
    expect("hover exit outside activation hides transiently", idleApp.menuBarManager.sections.allSatisfy { $0.controlItem.state == .hideItems && $0.persistedWrites == 0 })

    let (insideApp, _, _) = setup()
    for section in insideApp.menuBarManager.sections { section.setState(.showItems, persist: false) }
    let insideHover = EventManager()
    insideHover.appState = insideApp
    insideHover.mouseInsideIceBar = true
    insideHover.handleShowOnHover()
    await until("hover inside Ice Bar") { insideHover.outsideChecks > 0 }
    expect("hovering inside Ice Bar does not hide items", insideApp.menuBarManager.sections.allSatisfy { $0.controlItem.state == .showItems })

    let (scrollApp, scrollPanel, scrollContent) = setup()
    scrollContent.press(AXRowItem())
    await menuObserved()
    let scroll = EventManager()
    scroll.appState = scrollApp
    scroll.isMouseInsideMenuBar = true
    scroll.handleShowOnScroll(with: ScrollEvent(scrollingDeltaX: -10, scrollingDeltaY: -10))
    expect("explicit scroll hide remains authoritative during activation", scrollApp.menuBarManager.sections.allSatisfy { $0.controlItem.state == .hideItems && $0.persistedWrites == 1 })
    await finish(scrollPanel)

    for (inFlight, queuedIDs) in [(false, [2]), (false, [2, 3]), (true, [2]), (true, [2, 3])] {
        let (queueApp, queuePanel, queueContent) = setup()
        server.update { $0.pausePress = inFlight }
        queueContent.press(AXRowItem())
        if inFlight {
            await until("AX press entry") { server.snapshot.presses == [1] }
        } else {
            await menuObserved()
        }
        let previous = completion(of: queuePanel.axActivationTask)
        let menuReads = server.snapshot.menuReads
        // A third request supersedes only the queued second request, not the active popup.
        for id in queuedIDs { queueContent.press(AXRowItem(item: .init(testID: id))) }
        server.update { $0.pausePress = false }
        await until("continued popup observation after queued clicks") {
            server.snapshot.menuReads >= menuReads + 2 || previous.done
        }
        expect("\(queuedIDs.count) queued clicks protect \(inFlight ? "in-flight press" : "open popup")", !previous.done && server.snapshot.hidesWhileOpen == 0 && server.snapshot.presses == [1] && queueApp.menuBarManager.sections.allSatisfy { $0.controlItem.state == .showItems })
        queueApp.menuBarManager.sections[1].setState(.showItems, persist: true)
        server.update { $0.menuOpen = false }
        let latestID = queuedIDs[queuedIDs.count - 1]
        await until("latest queued press") { server.snapshot.presses.contains(latestID) }
        let queuedReads = server.snapshot.menuReads
        await until("queued popup observation") { server.snapshot.menuReads >= queuedReads + 2 }
        expect("only the latest queued request presses", server.snapshot.presses == [1, latestID])
        await finish(queuePanel)
        expect("queued activation preserves the newer user choice", queueApp.menuBarManager.sections[1].controlItem.state == .showItems && queueApp.menuBarManager.sections[1].persistedWrites == 1)
    }
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
    .replacingOccurrences(of: "    // PRODUCTION_HOVER", with: hoverMethod)
    .replacingOccurrences(of: "    // PRODUCTION_SCROLL", with: scrollMethod)
try (productionFixtures + "\n" + activationMethod + "\n" + middle + "\n" + rowMethod + "\n" + tests)
    .write(to: generated, atomically: true, encoding: .utf8)
let runner = Process()
runner.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
runner.arguments = [generated.path]
try runner.run()
let watchdog = DispatchWorkItem {
    if runner.isRunning {
        print("FAIL: activation test process exceeded its 60-second deadline")
        runner.terminate()
    }
}
DispatchQueue.global().asyncAfter(deadline: .now() + 60, execute: watchdog)
runner.waitUntilExit()
watchdog.cancel()
let status = runner.terminationStatus
try FileManager.default.removeItem(at: directory)
exit(status)
