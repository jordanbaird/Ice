import CoreGraphics
import Testing
@testable import IceMacOS27Core

@Suite("SectionLayout27")
struct SectionLayout27Tests {
    @Test("An app takes its most visible section")
    func appTakesMostVisibleSection() {
        let result = SectionLayout27.appSections(items: [
            (bundleID: "eu.exelban.Stats", section: .hidden),
            (bundleID: "eu.exelban.Stats", section: .visible),
            (bundleID: "ru.keepcoder.Telegram", section: .alwaysHidden),
        ])
        #expect(result == ["eu.exelban.Stats": .visible, "ru.keepcoder.Telegram": .alwaysHidden])
    }

    @Test("Observed sections win over the saved layout")
    func observedWins() {
        let result = SectionLayout27.effectiveLayout(
            observed: ["com.caldis.Mos": .visible],
            saved: ["com.caldis.Mos": .alwaysHidden],
            running: ["com.caldis.Mos"]
        )
        #expect(result == ["com.caldis.Mos": .visible])
    }

    @Test("The saved layout covers apps that could not be read")
    func savedCoversUnreadApps() {
        let result = SectionLayout27.effectiveLayout(
            observed: [:],
            saved: ["com.ethanbills.DockDoor": .hidden],
            running: ["com.ethanbills.DockDoor"]
        )
        #expect(result == ["com.ethanbills.DockDoor": .hidden])
    }

    @Test("Apps seen for the first time are visible")
    func newAppsAreVisible() {
        let result = SectionLayout27.effectiveLayout(observed: [:], saved: [:], running: ["com.example.New"])
        #expect(result == ["com.example.New": .visible])
    }

    @Test("Only running apps are part of the layout")
    func onlyRunningApps() {
        let result = SectionLayout27.effectiveLayout(observed: [:], saved: ["com.example.Quit": .hidden], running: [])
        #expect(result.isEmpty)
    }

    @Test("Bundles are collected by section")
    func bundlesBySection() {
        let layout: [String: MacOS27Section] = ["a": .visible, "b": .hidden, "c": .alwaysHidden]
        #expect(SectionLayout27.bundles(in: [.hidden, .alwaysHidden], layout: layout) == ["b", "c"])
        #expect(SectionLayout27.bundles(in: [.alwaysHidden], layout: layout) == ["c"])
    }
}
@Suite("Seeding the macOS 27 layout from the bar")
struct SeededLayout27Tests {
    // A bar as it stood before macOS 27: always-hidden items, the always-hidden divider,
    // hidden items, the hidden divider, then the visible ones.
    let alwaysHiddenDivider = CGRect(x: 1000, y: 0, width: 2, height: 24)
    let hiddenDivider = CGRect(x: 1200, y: 0, width: 2, height: 24)

    func item(_ bundleID: String, x: CGFloat) -> (bundleID: String, bounds: CGRect) {
        (bundleID, CGRect(x: x, y: 0, width: 30, height: 24))
    }

    @Test("Each divider places the items around it")
    func sections() {
        let layout = SectionLayout27.seededLayout(
            items: [item("com.caldis.Mos", x: 900), item("ru.keepcoder.Telegram", x: 1100), item("eu.exelban.Stats", x: 1300)],
            hiddenControlItem: hiddenDivider,
            alwaysHiddenControlItem: alwaysHiddenDivider
        )
        #expect(layout == [
            "com.caldis.Mos": .alwaysHidden,
            "ru.keepcoder.Telegram": .hidden,
            "eu.exelban.Stats": .visible,
        ])
    }

    @Test("An application with items in two sections takes the most visible one")
    func mostVisibleWins() {
        let layout = SectionLayout27.seededLayout(
            items: [item("eu.exelban.Stats", x: 1100), item("eu.exelban.Stats", x: 1300)],
            hiddenControlItem: hiddenDivider,
            alwaysHiddenControlItem: alwaysHiddenDivider
        )
        #expect(layout == ["eu.exelban.Stats": .visible])
    }

    @Test("Without an always-hidden divider nothing is always hidden")
    func noAlwaysHiddenDivider() {
        let layout = SectionLayout27.seededLayout(
            items: [item("com.caldis.Mos", x: 900), item("eu.exelban.Stats", x: 1300)],
            hiddenControlItem: hiddenDivider,
            alwaysHiddenControlItem: nil
        )
        #expect(layout == ["com.caldis.Mos": .hidden, "eu.exelban.Stats": .visible])
    }

    @Test("A bar with nothing to the right of the hidden divider is not read")
    func dividersAtTheEnd() {
        // macOS 27 reorders items itself, so on a bar it has already rearranged the dividers
        // drift to the end and everything would read as hidden. Say nothing instead.
        let layout = SectionLayout27.seededLayout(
            items: [item("com.caldis.Mos", x: 900), item("ru.keepcoder.Telegram", x: 1100)],
            hiddenControlItem: hiddenDivider,
            alwaysHiddenControlItem: alwaysHiddenDivider
        )
        #expect(layout == nil)
    }

    @Test("An item lying across a divider is left out")
    func straddling() {
        let layout = SectionLayout27.seededLayout(
            items: [item("com.caldis.Mos", x: 1190), item("eu.exelban.Stats", x: 1300)],
            hiddenControlItem: hiddenDivider,
            alwaysHiddenControlItem: alwaysHiddenDivider
        )
        #expect(layout == ["eu.exelban.Stats": .visible])
    }

    @Test("An empty bar is not read")
    func empty() {
        #expect(SectionLayout27.seededLayout(items: [], hiddenControlItem: hiddenDivider, alwaysHiddenControlItem: nil) == nil)
    }
}
