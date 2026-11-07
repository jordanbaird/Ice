//
//  Migration.swift
//  Ice
//

import Cocoa
import OSLog

// FIXME: Migration has gotten extremely messy. It should really just be completely redone at this point.
// TODO: Decide what needs to stay in the new implementation, and what has been around long enough that it can be removed.
@MainActor
struct MigrationManager {
    private let logger = Logger(category: "Migration")

    let appState: AppState
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
}

// MARK: - Migrate All

extension MigrationManager {
    /// Performs all migrations.
    func migrateAll() {
        var results = [MigrationResult]()

        do {
            try performAll(blocks: [
                migrate0_8_0,
                migrate0_10_0,
            ])
        } catch let error as MigrationError {
            results.append(.failureAndLogError(error))
        } catch {
            logger.error("Migration failed with unknown error \(error)")
        }

        results += [
            migrate0_10_1(),
            migrate0_11_10(),
            migrate0_11_13(),
            migrate0_11_13_1(),
        ]

        for result in results {
            switch result {
            case .success:
                continue
            case .successButShowAlert(let alert):
                alert.runModal()
            case .failureAndLogError(let error):
                logger.error("Migration failed with error \(error, privacy: .public)")
            }
        }
    }
}

// MARK: - Migrate 0.8.0

extension MigrationManager {
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
        logger.info("Successfully migrated to 0.8.0 settings")
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
                let sectionDict = sectionsArray.first(where: { $0["name"] as? String == name.rawValue0_8_0 }),
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
            let hotkeysSettings = appState.settings.hotkeys
            if case .hidden = name {
                if let hotkey = hotkeysSettings.hotkey(withAction: .toggleHiddenSection) {
                    hotkey.keyCombination = keyCombination
                }
            } else if case .alwaysHidden = name {
                if let hotkey = hotkeysSettings.hotkey(withAction: .toggleAlwaysHiddenSection) {
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

        for name in MenuBarSection.Name.allCases {
            guard
                var sectionDict = sectionsArray.first(where: { $0["name"] as? String == name.rawValue0_8_0 }),
                var controlItemDict = sectionDict["controlItem"] as? [String: Any],
                // remove the "autosaveName" key from the dictionary
                let autosaveName = controlItemDict.removeValue(forKey: "autosaveName") as? String
            else {
                continue
            }

            let identifier = switch name {
            case .visible:
                ControlItem.Identifier.visible.rawValue0_8_0
            case .hidden:
                ControlItem.Identifier.hidden.rawValue0_8_0
            case .alwaysHidden:
                ControlItem.Identifier.alwaysHidden.rawValue0_8_0
            }

            // add the "identifier" key to the dictionary
            controlItemDict["identifier"] = identifier

            // migrate the old autosave name to the new autosave name in UserDefaults
            ControlItemDefaults.migrate(key: .preferredPosition, from: autosaveName, to: identifier)
            ControlItemDefaults.migrate(key: .visible, from: autosaveName, to: identifier)

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
}

// MARK: - Migrate 0.10.0

extension MigrationManager {
    /// Performs all migrations for the `0.10.0` release.
    private func migrate0_10_0() {
        guard !Defaults.bool(forKey: .hasMigrated0_10_0) else {
            return
        }

        migrateControlItems0_10_0()

        Defaults.set(true, forKey: .hasMigrated0_10_0)
        logger.info("Successfully migrated to 0.10.0 settings")
    }

    private func migrateControlItems0_10_0() {
        for identifier in ControlItem.Identifier.allCases {
            ControlItemDefaults.migrate(
                key: .preferredPosition,
                from: identifier.rawValue0_8_0,
                to: identifier.rawValue0_10_0
            )
        }
    }
}

// MARK: - Migrate 0.10.1

extension MigrationManager {
    /// Performs all migrations for the `0.10.1` release.
    private func migrate0_10_1() -> MigrationResult {
        guard !Defaults.bool(forKey: .hasMigrated0_10_1) else {
            return .success
        }
        let result = migrateControlItems0_10_1()
        switch result {
        case .success, .successButShowAlert:
            Defaults.set(true, forKey: .hasMigrated0_10_1)
            logger.info("Successfully migrated to 0.10.1 settings")
        case .failureAndLogError:
            break
        }
        return result
    }

    private func migrateControlItems0_10_1() -> MigrationResult {
        var needsResetPreferredPositions = false

        for identifier in ControlItem.Identifier.allCases {
            if
                ControlItemDefaults[.visible, identifier.rawValue0_10_0] == false,
                ControlItemDefaults[.preferredPosition, identifier.rawValue0_10_0] == nil
            {
                needsResetPreferredPositions = true
            }
            ControlItemDefaults[.visible, identifier.rawValue0_10_0] = nil
        }

        if needsResetPreferredPositions {
            for identifier in ControlItem.Identifier.allCases {
                ControlItemDefaults[.preferredPosition, identifier.rawValue0_10_0] = nil
            }

            let alert = NSAlert()
            alert.messageText = """
                Due to a bug in a previous version of the app, the data for \
                Ice’s menu bar sections was corrupted and had to be reset.
                """

            return .successButShowAlert(alert)
        }

        return .success
    }
}

// MARK: - Migrate 0.11.10

extension MigrationManager {
    /// Performs all migrations for the `0.11.10` release.
    private func migrate0_11_10() -> MigrationResult {
        guard !Defaults.bool(forKey: .hasMigrated0_11_10) else {
            return .success
        }
        let result = migrateAppearanceConfiguration0_11_10()
        switch result {
        case .success, .successButShowAlert:
            Defaults.set(true, forKey: .hasMigrated0_11_10)
            logger.info("Successfully migrated to 0.11.10 settings")
        case .failureAndLogError:
            break
        }
        return result
    }

    private func migrateAppearanceConfiguration0_11_10() -> MigrationResult {
        guard let oldData = Defaults.data(forKey: .menuBarAppearanceConfiguration) else {
            if Defaults.object(forKey: .menuBarAppearanceConfiguration) != nil {
                logger.warning("Previous menu bar appearance data is corrupted")
            }
            // This is either the first launch, or the data is malformed.
            // Either way, not much to do here.
            return .success
        }
        do {
            let oldConfiguration = try decoder.decode(MenuBarAppearanceConfigurationV1.self, from: oldData)
            let newConfiguration = withMutableCopy(of: MenuBarAppearanceConfigurationV2.defaultConfiguration) { configuration in
                let partialConfiguration = MenuBarAppearancePartialConfiguration(
                    hasShadow: oldConfiguration.hasShadow,
                    hasBorder: oldConfiguration.hasBorder,
                    borderColor: oldConfiguration.borderColor,
                    borderWidth: oldConfiguration.borderWidth,
                    tintKind: oldConfiguration.tintKind,
                    tintColor: oldConfiguration.tintColor,
                    tintGradient: oldConfiguration.tintGradient
                )
                configuration.lightModeConfiguration = partialConfiguration
                configuration.darkModeConfiguration = partialConfiguration
                configuration.staticConfiguration = partialConfiguration
                configuration.shapeKind = oldConfiguration.shapeKind
                configuration.fullShapeInfo = oldConfiguration.fullShapeInfo
                configuration.splitShapeInfo = oldConfiguration.splitShapeInfo
                configuration.isInset = oldConfiguration.isInset
            }
            let newData = try encoder.encode(newConfiguration)
            Defaults.set(newData, forKey: .menuBarAppearanceConfigurationV2)
        } catch {
            return .failureAndLogError(.appearanceConfigurationMigrationError(error))
        }
        return .success
    }
}

// MARK: - Migrate 0.11.13

extension MigrationManager {
    /// Performs all migrations for the `0.11.13` release.
    private func migrate0_11_13() -> MigrationResult {
        guard !Defaults.bool(forKey: .hasMigrated0_11_13) else {
            return .success
        }

        migrateAppearanceConfiguration0_11_13()
        migrateSectionDividers0_11_13()

        Defaults.set(true, forKey: .hasMigrated0_11_13)
        logger.info("Successfully migrated to 0.11.13 settings")

        return .success
    }

    private func migrateAppearanceConfiguration0_11_13() {
        Defaults.removeObject(forKey: .menuBarAppearanceConfiguration)
    }

    private func migrateSectionDividers0_11_13() {
        let style = if Defaults.bool(forKey: .showSectionDividers) {
            SectionDividerStyle.chevron
        } else {
            SectionDividerStyle.noDivider
        }
        Defaults.set(style.rawValue, forKey: .sectionDividerStyle)
        Defaults.removeObject(forKey: .showSectionDividers)
    }
}

// MARK: - Migrate 0.11.13.1

extension MigrationManager {
    /// Performs all migrations for the `0.11.13.1` release.
    private func migrate0_11_13_1() -> MigrationResult {
        guard !Defaults.bool(forKey: .hasMigrated0_11_13_1) else {
            return .success
        }

        migrateControlItems0_11_13_1()

        Defaults.set(true, forKey: .hasMigrated0_11_13_1)
        logger.info("Successfully migrated to 0.11.13.1 settings")

        return .success
    }

    private func migrateControlItems0_11_13_1() {
        for identifier in ControlItem.Identifier.allCases {
            ControlItemDefaults.migrate(
                key: .preferredPosition,
                from: identifier.rawValue0_10_0,
                to: identifier.rawValue
            )
            ControlItemDefaults.migrate(
                key: .visible,
                from: identifier.rawValue0_10_0,
                to: identifier.rawValue
            )
            ControlItemDefaults.migrate(
                key: .visibleCC,
                from: identifier.rawValue0_10_0,
                to: identifier.rawValue
            )
        }
    }
}

// MARK: - Helpers

extension MigrationManager {
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

// MARK: - MigrationResult

extension MigrationManager {
    enum MigrationResult {
        case success
        case successButShowAlert(NSAlert)
        case failureAndLogError(MigrationError)
    }
}

// MARK: - MigrationError

extension MigrationManager {
    enum MigrationError: Error, CustomStringConvertible {
        case invalidMenuBarSectionsJSONObject(Any)
        case hotkeyMigrationError(any Error)
        case controlItemMigrationError(any Error)
        case appearanceConfigurationMigrationError(any Error)
        case combinedError([any Error])

        var description: String {
            switch self {
            case .invalidMenuBarSectionsJSONObject(let object):
                "Invalid menu bar sections JSON object: \(object)"
            case .hotkeyMigrationError(let error):
                "Error migrating hotkeys: \(error)"
            case .controlItemMigrationError(let error):
                "Error migrating control items: \(error)"
            case .appearanceConfigurationMigrationError(let error):
                "Error migrating menu bar appearance configuration: \(error)"
            case .combinedError(let errors):
                "The following errors occurred: \(errors)"
            }
        }
    }
}

// MARK: - ControlItem.Identifier Extension

private extension ControlItem.Identifier {
    var rawValue0_8_0: String {
        switch self {
        case .visible: "IceIcon"
        case .hidden: "HItem"
        case .alwaysHidden: "AHItem"
        }
    }

    var rawValue0_10_0: String {
        switch self {
        case .visible: "SItem"
        case .hidden: "HItem"
        case .alwaysHidden: "AHItem"
        }
    }
}

// MARK: - MenuBarSection.Name Extension

private extension MenuBarSection.Name {
    var rawValue0_8_0: String {
        switch self {
        case .visible: "Visible"
        case .hidden: "Hidden"
        case .alwaysHidden: "Always Hidden"
        }
    }
}
