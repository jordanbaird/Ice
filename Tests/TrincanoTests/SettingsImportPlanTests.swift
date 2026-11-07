//
//  SettingsImportPlanTests.swift
//  TrincanoTests
//

import Testing

struct SettingsImportPlanTests {
    private let allowed: Set<String> = ["UseIceBar", "ShowOnClick"]

    @Test func importsOnlyKnownKeys() {
        let source: [String: Any] = ["UseIceBar": true, "SUHasLaunchedBefore": true, "Other": 1]
        let result = SettingsImportPlan.valuesToImport(source: source, allowedKeys: allowed, existingKeys: [])
        #expect(Set(result.keys) == ["UseIceBar"])
    }

    @Test func neverOverwritesExistingValues() {
        let source: [String: Any] = ["UseIceBar": true, "ShowOnClick": false]
        let result = SettingsImportPlan.valuesToImport(source: source, allowedKeys: allowed, existingKeys: ["UseIceBar"])
        #expect(Set(result.keys) == ["ShowOnClick"])
    }

    @Test func keepsControlItemPositions() {
        let key = SettingsImportPlan.controlItemPositionPrefix + "Hidden"
        let result = SettingsImportPlan.valuesToImport(source: [key: 120.0], allowedKeys: allowed, existingKeys: [])
        #expect(result[key] as? Double == 120.0)
    }

    @Test func keepsControlItemVisibilityKeys() {
        let keys = ["NSStatusItem Visible Ice.ControlItem.Hidden", "NSStatusItem VisibleCC Ice.ControlItem.Visible"]
        let source = Dictionary(uniqueKeysWithValues: keys.map { ($0, true as Any) })
        let result = SettingsImportPlan.valuesToImport(source: source, allowedKeys: allowed, existingKeys: [])
        #expect(Set(result.keys) == Set(keys))
    }

    @Test func emptySourceImportsNothing() {
        #expect(SettingsImportPlan.valuesToImport(source: [:], allowedKeys: allowed, existingKeys: []).isEmpty)
    }

    @Test func doesNotCopySparkleOrSystemKeys() {
        let source: [String: Any] = ["SUEnableAutomaticChecks": true, "NSWindow Frame Foo": "x"]
        #expect(SettingsImportPlan.valuesToImport(source: source, allowedKeys: allowed, existingKeys: []).isEmpty)
    }
}
