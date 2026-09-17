// Compile with Ice/MenuBar/MenuBarItems/MacOS27DynamicItemState.swift.
import Foundation

@main
enum MacOS27LayoutOwnerTests {
    static func main() {
        typealias Registry = MacOS27LayoutOwnerRegistry<String>
        typealias Owner = Registry.Owner
        var assertions = 0
        func check(_ condition: Bool, _ description: String) {
            precondition(condition, description)
            assertions += 1
            print("PASS: \(description)")
        }
        let plugin = Owner(pid: 10, namespace: "plugin", launchTime: 1)
        let ordinary = Owner(pid: 20, namespace: "ordinary", launchTime: 2)
        let newApp = Owner(pid: 30, namespace: "new-app", launchTime: 3)
        var registry = Registry()
        registry.observe([plugin])
        registry.runningApplicationsChanged([plugin, ordinary])
        check(registry.targets(runningOwners: [plugin, ordinary]).sourcePIDs.isEmpty,
              "no Layout session means no additional refresh owners")
        registry.begin(knownOwners: [plugin], runningOwners: [plugin, ordinary])
        check(registry.targets(runningOwners: [plugin, ordinary]).sourcePIDs == [10],
              "entering Layout seeds only known status-item owners, not all running apps")
        registry.observe([])
        check(registry.targets(runningOwners: [plugin, ordinary]).sourcePIDs == [10],
              "withdrawing the final tile does not remove its living owner from refreshes")
        registry.runningApplicationsChanged([plugin, ordinary])
        check(registry.targets(runningOwners: [plugin, ordinary]).sourcePIDs == [10],
              "an unchanged application-list notification does not add unrelated apps")
        registry.runningApplicationsChanged([plugin, ordinary, newApp])
        check(registry.targets(runningOwners: [plugin, ordinary, newApp]).sourcePIDs == [10, 30],
              "only a newly launched app joins the session refresh set")
        registry.observe([])
        check(registry.targets(runningOwners: [plugin, ordinary, newApp]).sourcePIDs.contains(30),
              "a newly launched host can publish its first item after a delay")
        registry.begin(knownOwners: [], runningOwners: [plugin, ordinary, newApp])
        check(registry.targets(runningOwners: [plugin, ordinary, newApp]).sourcePIDs == [10, 30],
              "duplicate editor-entry callbacks do not reset the live session")
        registry.runningApplicationsChanged([ordinary, newApp])
        let afterExit = registry.targets(runningOwners: [ordinary, newApp])
        check(!afterExit.sourcePIDs.contains(10), "exited process IDs stop receiving direct AX reads")
        check(afterExit.namespaces.contains("plugin"), "an observed namespace remains available for restart resolution")
        let recycledPID = Owner(pid: 10, namespace: "unrelated", launchTime: 4)
        check(!registry.targets(runningOwners: [ordinary, newApp, recycledPID]).sourcePIDs.contains(10),
              "a recycled PID is not treated as the previously observed process")
        let restarted = Owner(pid: 40, namespace: "plugin", launchTime: 5)
        registry.runningApplicationsChanged([ordinary, newApp, restarted])
        check(registry.targets(runningOwners: [ordinary, newApp, restarted]).sourcePIDs.contains(40),
              "a replacement process lifetime is admitted by the launch delta")
        let samePIDNewLifetime = Owner(pid: 40, namespace: "plugin", launchTime: 6)
        check(!registry.targets(runningOwners: [ordinary, newApp, samePIDNewLifetime]).sourcePIDs.contains(40),
              "same PID and namespace still require the observed launch lifetime")
        registry.observe([ordinary])
        check(registry.targets(runningOwners: [ordinary, newApp, restarted]).sourcePIDs.contains(20),
              "an explicit full refresh can add an already-running previously unseen owner")
        registry.end()
        let ended = registry.targets(runningOwners: [ordinary, newApp, restarted])
        check(ended.sourcePIDs.isEmpty && ended.namespaces.isEmpty,
              "ending the editor session clears its transient owner scope")
        registry.begin(knownOwners: [restarted], runningOwners: [ordinary, newApp, restarted])
        check(registry.targets(runningOwners: [ordinary, newApp, restarted]).sourcePIDs == [40],
              "a new Layout session does not inherit old auxiliary owner entries")
        print("\(assertions) Layout-owner assertions passed")
    }
}
