// Compile with Ice/MenuBar/MenuBarItems/MacOS27DynamicItemState.swift.
import ApplicationServices
import Foundation

@main
enum MacOS27DynamicItemStateTests {
    struct Element {
        var id: Int
        var label: String
    }

    static func main() {
        var assertions = 0
        func check(_ condition: Bool, _ description: String) {
            precondition(condition, description)
            assertions += 1
            print("PASS: \(description)")
        }
        let sameObject: (Element, Element) -> Bool = { $0.id == $1.id }
        let initial = Element(id: 10, label: "CPU 20%")
        let updated = Element(id: 10, label: "CPU 80%")
        // Minimal old-path reproduction: identifier ?? description ?? title
        // changed the identity even though only a status label had changed.
        check(initial.label != updated.label, "old description-based identities differ on a label update")
        var registry = MacOS27RuntimeItemRegistry<Element>(capacity: 3)
        let first = registry.identity(for: initial, owner: "A", now: 0, equals: sameObject)
        check(first == registry.identity(for: updated, owner: "A", now: 1, equals: sameObject),
              "a changing label keeps the same runtime identity")
        let second = registry.identity(for: Element(id: 11, label: "CPU 80%"), owner: "A", now: 2, equals: sameObject)
        check(first != second, "equal labels do not merge distinct menu items")
        check(second == registry.identity(for: Element(id: 11, label: "Other"), owner: "A", now: 3, equals: sameObject),
              "the second item retains its identity when enumerated first")
        check(first == registry.identity(for: updated, owner: "A", now: 4, equals: sameObject),
              "reversing enumeration order does not swap identities")
        let replacement = registry.identity(for: Element(id: 12, label: initial.label), owner: "A", now: 5, equals: sameObject)
        check(replacement != first, "unequal reconstructed objects are not guessed from their old label")
        check(registry.count == 3, "registry reaches but does not exceed its configured bound")
        let otherOwner = registry.identity(for: updated, owner: "B", now: 6, equals: sameObject)
        check(otherOwner != first, "the same object key in a different owner lifetime is distinct")
        check(registry.count == 3, "inserting a fourth object evicts the least recently observed reference")
        check(first == registry.identity(for: updated, owner: "A", now: 7, equals: sameObject),
              "a more recently observed object survives bounded eviction")
        registry.removeUnavailableOwners(["A"])
        check(registry.count == 2, "references from an exited owner are removed")
        let longHidden = registry.identity(for: updated, owner: "A", now: 36_000, equals: sameObject)
        check(longHidden == first, "long concealment does not expire a live owner's item identity")
        registry.removeUnavailableOwners([])
        check(registry.count == 0, "exited owners release all their retained references")
        let fresh = registry.identity(for: updated, owner: "A", now: 36_001, equals: sameObject)
        check(fresh != first, "an exited owner's reference is not rebound by label or position")
        var newSession = MacOS27RuntimeItemRegistry<Element>()
        check(fresh != newSession.identity(for: updated, owner: "A", now: 19, equals: sameObject),
              "runtime tokens cannot collide across Ice launches")
        check(MacOS27RuntimeItemIdentity.isStoredIdentifier("org.swiftbar:\(fresh)#0"),
              "persisted runtime assignments can be removed on restart")
        check(!MacOS27RuntimeItemIdentity.isStoredIdentifier("com.apple.controlcenter:com.apple.menuextra.wifi#0"),
              "deterministic system assignments are not treated as runtime tokens")

        var grace = MacOS27MissingItemGrace()
        check(!grace.needsVerification("plugin", canObserve: true, now: 0),
              "a first expanded omission keeps the tile")
        check(!grace.needsVerification("plugin", canObserve: true, now: 1.9),
              "short AX reflow does not request deletion")
        check(grace.needsVerification("plugin", canObserve: true, now: 2),
              "a repeated omission after two seconds requires an owner reread")
        check(!grace.needsVerification("plugin", canObserve: false, now: 100),
              "concealment, reordering or an empty whole-bar read suspend the grace period")
        check(!grace.needsVerification("plugin", canObserve: true, now: 101),
              "time spent concealed does not count as expanded absence")
        grace.saw("plugin")
        check(!grace.needsVerification("plugin", canObserve: true, now: 110),
              "a republished live item resets its old missing observation")
        check(grace.needsVerification("plugin", canObserve: true, now: 112),
              "a running owner cannot grant an indefinitely retained ghost tile")

        let strip = CGRect(x: 0, y: 0, width: 1000, height: 40)
        let onscreen = CGRect(x: 100, y: 4, width: 30, height: 24)
        let overflow = CGRect(x: -400, y: 1000, width: 30, height: 24)
        func includes(_ frame: CGRect, existenceOnly: Bool) -> Bool {
            MacOS27ItemSnapshotGeometry.includes(
                frame: frame, menuBarFrames: [strip], maxItemHeight: 40,
                includingOffscreenItems: existenceOnly
            )
        }
        check(includes(onscreen, existenceOnly: false), "ordinary enumeration includes real menu-bar geometry")
        check(!includes(overflow, existenceOnly: false), "ordinary enumeration excludes overflow frames from drag targets")
        check(includes(overflow, existenceOnly: true), "an off-bar AX child still proves the item was not withdrawn")
        check(!includes(.zero, existenceOnly: false), "zero-size native transition frames are not actionable")
        check(includes(.zero, existenceOnly: true), "a zero-size published child prevents false withdrawal during reflow")

        // This verifies CF equality of separately created application handles,
        // not stability of remote status-item scenes or a SwiftBar UI test.
        var nativeRegistry = MacOS27RuntimeItemRegistry<AXUIElement>()
        let app1 = AXUIElementCreateApplication(getpid())
        let app2 = AXUIElementCreateApplication(getpid())
        let native = nativeRegistry.identity(for: app1, owner: "self", now: 0, equals: { CFEqual($0, $1) })
        check(native == nativeRegistry.identity(for: app2, owner: "self", now: 1, equals: { CFEqual($0, $1) }),
              "separately created equal AX handles map to the same token without pointer comparison")
        print("\(assertions) dynamic-item assertions passed")
    }
}
