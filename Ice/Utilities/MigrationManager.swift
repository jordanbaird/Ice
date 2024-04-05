//
//  MigrationManager.swift
//  Ice
//

import Foundation
import OSLog

struct MigrationManager {
    enum MigrationError: Error, CustomStringConvertible {
        case invalidMenuBarSectionsJSONObject(Any)
        case hotkeyMigrationError(any Error)
        case controlItemMigrationError(any Error)
        case combinedError([any Error])

        var description: String {
            switch self {
            case .invalidMenuBarSectionsJSONObject(let object):
                "Invalid menu bar sections JSON object: \(object)"
            case .hotkeyMigrationError(let error):
                "Error migrating hotkeys: \(error)"
            case .controlItemMigrationError(let error):
                "Error migrating control items: \(error)"
            case .combinedError(let errors):
                "The following errors occurred: \(errors)"
            }
        }
    }

    let appState: AppState

    // MARK: Migrate All

    /// Performs all migrations.
    func migrateAll() {
        do {
            try performAll(blocks: [migrate0_8_0])
        } catch {
            Logger.migration.error("Migration failed with error: \(error)")
        }
    }

    /// Performs all migrations for the `0.8.0` release, catching any thrown
    /// errors and rethrowing them as a combined error.
    private func migrate0_8_0() throws {
        guard !Defaults.bool(forKey: .hasMigrated0_8_0) else {
            return
        }
        try performAll(blocks: [
            migrateHotkeys0_8_0,
            migrateControlItems0_8_0,
            migrateSections0_8_0,
        ])
        Defaults.set(true, forKey: .hasMigrated0_8_0)
        Logger.migration.info("Successfully migrated to 0.8.0 settings")
    }

    // MARK: Migrate Hotkeys

    /// Migrates the user's saved hotkeys from the old method of storing
    /// them in their corresponding menu bar sections to the new method
    /// of storing them as stand-alone data in the `0.8.0` release.
    private func migrateHotkeys0_8_0() throws {
        let sectionsArray: [[String: Any]]
        do {
            guard let array = try getMenuBarSectionArray() else {
                return
            }
            sectionsArray = array
        } catch {
            throw MigrationError.hotkeyMigrationError(error)
        }

        // get the hotkey data from the hidden and always-hidden sections,
        // if available, and create equivalent key combinations to assign
        // to the corresponding hotkeys
        for name: MenuBarSection.Name in [.hidden, .alwaysHidden] {
            guard
                let sectionDict = sectionsArray.first(where: { $0["name"] as? String == name.deprecatedRawValue }),
                let hotkeyDict = sectionDict["hotkey"] as? [String: Int],
                let key = hotkeyDict["key"],
                let modifiers = hotkeyDict["modifiers"]
            else {
                continue
            }
            let keyCombination = KeyCombination(
                key: KeyCode(rawValue: key),
                modifiers: Modifiers(rawValue: modifiers)
            )
            let hotkeySettingsManager = appState.settingsManager.hotkeySettingsManager
            if case .hidden = name {
                if let hotkey = hotkeySettingsManager.hotkey(withAction: .toggleHiddenSection) {
                    hotkey.keyCombination = keyCombination
                }
            } else if case .alwaysHidden = name {
                if let hotkey = hotkeySettingsManager.hotkey(withAction: .toggleAlwaysHiddenSection) {
                    hotkey.keyCombination = keyCombination
                }
            }
        }
    }

    // MARK: Migrate Control Items

    /// Migrates the control items from their old serialized representations
    /// to their new representations in the `0.8.0` release.
    private func migrateControlItems0_8_0() throws {
        let sectionsArray: [[String: Any]]
        do {
            guard let array = try getMenuBarSectionArray() else {
                return
            }
            sectionsArray = array
        } catch {
            throw MigrationError.controlItemMigrationError(error)
        }

        var newSectionsArray = [[String: Any]]()

        for name: MenuBarSection.Name in [.visible, .hidden, .alwaysHidden] {
            guard
                var sectionDict = sectionsArray.first(where: { $0["name"] as? String == name.deprecatedRawValue }),
                var controlItemDict = sectionDict["controlItem"] as? [String: Any],
                // remove the "autosaveName" key from the dictionary
                let autosaveName = controlItemDict.removeValue(forKey: "autosaveName") as? String
            else {
                continue
            }

            let identifier = switch name {
            case .visible:
                ControlItem.Identifier.iceIcon.rawValue
            case .hidden:
                ControlItem.Identifier.hidden.rawValue
            case .alwaysHidden:
                ControlItem.Identifier.alwaysHidden.rawValue
            }

            // add the "identifier" key to the dictionary
            controlItemDict["identifier"] = identifier

            // migrate the old autosave name to the new autosave name in UserDefaults
            StatusItemDefaults.migrate(key: .preferredPosition, from: autosaveName, to: identifier)
            StatusItemDefaults.migrate(key: .isVisible, from: autosaveName, to: identifier)

            // replace the old "controlItem" dictionary with the new one
            sectionDict["controlItem"] = controlItemDict
            // add the section to the new array
            newSectionsArray.append(sectionDict)
        }

        do {
            let data = try JSONSerialization.data(withJSONObject: newSectionsArray)
            Defaults.set(data, forKey: .sections)
        } catch {
            throw MigrationError.controlItemMigrationError(error)
        }
    }

    /// Migrates away from storing the menu bar sections in UserDefaults
    /// for the `0.8.0` release.
    private func migrateSections0_8_0() {
        Defaults.set(nil, forKey: .sections)
    }

    // MARK: Helpers

    /// Performs every block in the given array, catching any thrown
    /// errors and rethrowing them as a combined error.
    private func performAll(blocks: [() throws -> Void]) throws {
        let results = blocks.map { block in
            Result(catching: block)
        }
        let errors = results.compactMap { result in
            if case .failure(let error) = result {
                return error
            }
            return nil
        }
        if !errors.isEmpty {
            throw MigrationError.combinedError(errors)
        }
    }

    /// Returns an array of dictionaries that represent the sections in
    /// the menu bar, as stored in UserDefaults.
    private func getMenuBarSectionArray() throws -> [[String: Any]]? {
        guard let data = Defaults.data(forKey: .sections) else {
            return nil
        }
        let object = try JSONSerialization.jsonObject(with: data)
        guard let array = object as? [[String: Any]] else {
            throw MigrationError.invalidMenuBarSectionsJSONObject(object)
        }
        return array
    }
}

// MARK: - Logger
private extension Logger {
    static let migration = Logger(category: "Migration")
}
