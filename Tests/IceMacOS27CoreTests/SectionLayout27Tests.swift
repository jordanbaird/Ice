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
