import Foundation
import Testing
@testable import IceMacOS27Core

@Suite("TrackedApplications27")
struct TrackedApplications27Tests {
    // The shape MenuBarAgent writes, measured on macOS 27.0.1 (2026-10-22): key, value, key, value.
    static func bundleKey(_ id: String) -> [String: Any] {
        ["bundle": ["_0": id]]
    }

    static func value(for key: [String: Any], isAllowed: Bool) -> [String: Any] {
        ["location": key, "menuItemLocations": [key], "isAllowed": isAllowed]
    }

    static let adhocKey: [String: Any] = ["adhocBinary": ["_0": ["relative": "file:///Users/me/Developer/Ice/Ice"]]]

    let fixture: [Any] = [
        bundleKey("com.bitwarden.desktop"), value(for: bundleKey("com.bitwarden.desktop"), isAllowed: true),
        adhocKey, value(for: adhocKey, isAllowed: true),
        bundleKey("net.matthewpalmer.Horo"), value(for: bundleKey("net.matthewpalmer.Horo"), isAllowed: true),
        bundleKey("com.user.disallowed"), value(for: bundleKey("com.user.disallowed"), isAllowed: false),
    ]

    func same(_ lhs: [Any], _ rhs: [Any]) -> Bool {
        (lhs as NSArray).isEqual(to: rhs)
    }

    @Test("Reads the allowed state of each bundle, and nothing for other keys")
    func reads() {
        #expect(TrackedApplications27.allowedStates(in: fixture) == [
            "com.bitwarden.desktop": true,
            "net.matthewpalmer.Horo": true,
            "com.user.disallowed": false,
        ])
        #expect(TrackedApplications27.entries(in: fixture).map(\.bundleID) == [
            "com.bitwarden.desktop", nil, "net.matthewpalmer.Horo", "com.user.disallowed",
        ])
    }

    @Test("Flipping to false changes only the named bundle")
    func flipToFalse() {
        let (array, changed) = TrackedApplications27.settingAllowed(false, for: ["net.matthewpalmer.Horo"], in: fixture)
        #expect(changed == ["net.matthewpalmer.Horo"])
        #expect(TrackedApplications27.allowedStates(in: array) == [
            "com.bitwarden.desktop": true,
            "net.matthewpalmer.Horo": false,
            "com.user.disallowed": false,
        ])
        #expect(array.count == fixture.count)
        let value = array[5] as? [String: Any]
        #expect((value?["location"] as? NSDictionary)?.isEqual(to: Self.bundleKey("net.matthewpalmer.Horo")) == true)
        #expect((value?["menuItemLocations"] as? NSArray)?.isEqual(to: [Self.bundleKey("net.matthewpalmer.Horo")]) == true)
    }

    @Test("Flipping back restores the original exactly")
    func flipBack() {
        let hidden = TrackedApplications27.settingAllowed(false, for: ["com.bitwarden.desktop", "net.matthewpalmer.Horo"], in: fixture)
        #expect(hidden.changed == ["com.bitwarden.desktop", "net.matthewpalmer.Horo"])
        let shown = TrackedApplications27.settingAllowed(true, for: hidden.changed, in: hidden.array)
        #expect(shown.changed == hidden.changed)
        #expect(same(shown.array, fixture))
    }

    @Test("An unknown bundle, or one already as asked, changes nothing")
    func unknown() {
        let (array, changed) = TrackedApplications27.settingAllowed(false, for: ["com.example.missing", "com.user.disallowed"], in: fixture)
        #expect(changed.isEmpty)
        #expect(same(array, fixture))
    }

    @Test("Keys that are not bundle keys are passed through untouched")
    func nonBundlePreserved() {
        let (array, _) = TrackedApplications27.settingAllowed(false, for: ["com.bitwarden.desktop", "net.matthewpalmer.Horo"], in: fixture)
        #expect((array[2] as? NSDictionary)?.isEqual(to: Self.adhocKey) == true)
        #expect((array[3] as? NSDictionary)?.isEqual(to: Self.value(for: Self.adhocKey, isAllowed: true)) == true)
    }

    @Test("Round-trips through the binary property list exactly")
    func roundTrip() throws {
        let data = try TrackedApplications27.encode(fixture)
        let decoded = try #require(TrackedApplications27.decode(data))
        #expect(same(decoded, fixture))
        let unchanged = TrackedApplications27.settingAllowed(true, for: [], in: decoded)
        #expect(same(unchanged.array, fixture))
    }

    @Test("An unpaired element at the end is kept and not read")
    func unpaired() {
        let odd = fixture + [Self.bundleKey("com.trailing.key")]
        #expect(TrackedApplications27.entries(in: odd).count == 4)
        let (array, _) = TrackedApplications27.settingAllowed(false, for: ["com.trailing.key"], in: odd)
        #expect(same(array, odd))
    }
}
