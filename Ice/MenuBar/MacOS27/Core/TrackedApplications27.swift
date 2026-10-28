//
//  TrackedApplications27.swift
//  Ice
//

import Foundation

/// Pure rules for MenuBarAgent's own list of applications allowed in the menu bar.
///
/// macOS 27 has a switch per application, "Allow in the Menu Bar" in System Settings >
/// Control Center. MenuBarAgent keeps it in the `trackedApplications` preference of the
/// `group.com.apple.controlcenter` group container: data holding a binary property list, which
/// is a Swift `[TrackedApplicationLocation: TrackedApplication]` encoded by `Codable` — a flat
/// array that alternates key, value, key, value (measured on macOS 27.0.1, 2026-10-22). A key
/// is `{"bundle": {"_0": "<bundle id>"}}`, or `{"adhocBinary": {"_0": {"relative": "file:///…"}}}`
/// for a binary not signed by a team. A value is `{"location": <its key>, "menuItemLocations":
/// [<key>, …], "isAllowed": <Bool>}`.
///
/// Only bundle keys are ever read or changed here. Every other key, and everything in a value
/// besides `isAllowed`, is passed back exactly as it came: MenuBarAgent wrote it, and Ice has no
/// business reshaping it.
enum TrackedApplications27 {
    /// One key and value pair of the list.
    struct Entry: Equatable {
        /// The bundle identifier of the key, or `nil` for a key that is not a bundle key.
        let bundleID: String?

        /// The value's `isAllowed`, or `nil` if it has none.
        let isAllowed: Bool?

        /// Where the value stands in the flat array; its key is the element before it.
        let valueIndex: Int
    }

    /// The pairs of the flat array, in order. An unpaired element at the end is not an entry.
    static func entries(in array: [Any]) -> [Entry] {
        stride(from: 0, to: array.count - 1, by: 2).map { keyIndex in
            let value = array[keyIndex + 1] as? [String: Any]
            return Entry(
                bundleID: bundleID(ofKey: array[keyIndex]),
                isAllowed: value?["isAllowed"] as? Bool,
                valueIndex: keyIndex + 1
            )
        }
    }

    /// The bundle identifier a key names, or `nil` if it is not a bundle key.
    static func bundleID(ofKey key: Any) -> String? {
        guard
            let key = key as? [String: Any],
            key.count == 1,
            let bundle = key["bundle"] as? [String: Any]
        else {
            return nil
        }
        return bundle["_0"] as? String
    }

    /// The current `isAllowed` of each bundle in the list.
    ///
    /// Should a bundle appear twice, which MenuBarAgent has not been seen to write, it counts as
    /// allowed if either entry is.
    static func allowedStates(in array: [Any]) -> [String: Bool] {
        var states = [String: Bool]()
        for entry in entries(in: array) {
            guard let bundleID = entry.bundleID, let isAllowed = entry.isAllowed else {
                continue
            }
            states[bundleID] = (states[bundleID] ?? false) || isAllowed
        }
        return states
    }

    /// The list with `isAllowed` set for the given bundles, and the bundles it actually changed.
    ///
    /// Only the values under a bundle key for one of the identifiers are touched, and only their
    /// `isAllowed`; a value that is already as asked, or that has no `isAllowed` at all, is left
    /// alone. Everything else, the order included, comes back as it was.
    static func settingAllowed(_ allowed: Bool, for bundleIDs: Set<String>, in array: [Any]) -> (array: [Any], changed: Set<String>) {
        guard !bundleIDs.isEmpty else {
            return (array, [])
        }
        var result = array
        var changed = Set<String>()
        for entry in entries(in: array) {
            guard
                let bundleID = entry.bundleID,
                bundleIDs.contains(bundleID),
                let isAllowed = entry.isAllowed,
                isAllowed != allowed,
                var value = array[entry.valueIndex] as? [String: Any]
            else {
                continue
            }
            value["isAllowed"] = allowed
            result[entry.valueIndex] = value
            changed.insert(bundleID)
        }
        return (result, changed)
    }

    /// Decodes the preference's data into the flat array, or `nil` if it is not one.
    static func decode(_ data: Data) -> [Any]? {
        try? PropertyListSerialization.propertyList(from: data, format: nil) as? [Any]
    }

    /// Encodes the flat array the way MenuBarAgent stores it: as a binary property list.
    static func encode(_ array: [Any]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: array, format: .binary, options: 0)
    }
}
