//
//  NativeAllowListConcealer27.swift
//  Ice
//

import AppKit
import Foundation
import OSLog

/// Hides applications' menu bar items through macOS 27's own "Allow in the Menu Bar" switch.
///
/// The switch lives in System Settings > Control Center, one per application, and MenuBarAgent
/// keeps it in the `trackedApplications` preference of the `group.com.apple.controlcenter` group
/// container (see ``TrackedApplications27``). Measured on macOS 27.0.1, 2026-10-22: writing
/// `isAllowed = false` for an application fades its items out within about 250 ms and gives
/// their room back, and `true` brings them back — with no restart and no assessment-mode
/// restriction, so Control Centre's modules, the Focus item and the camera indicator among them,
/// stay where they are, and clicks on system items reach them as they would without Ice.
/// MenuBarAgent also consults the switch when an application creates its item, so one launched
/// while hidden is simply not drawn, rather than squashed as it is under assessment mode.
///
/// The write has to go through CoreFoundation's container-aware preference calls. A path-based
/// `defaults write` changed the file and nothing happened until MenuBarAgent restarted: only
/// the container-aware calls reach the `NSUserDefaults` observers MenuBarAgent keeps on it
/// (measured the same day).
///
/// The switch is the user's as much as Ice's, so Ice records every application it turns off,
/// in `MacOS27NativeDisallowed`, and turns back on only those. An application the user turned
/// off themselves is never touched. The record outlives Ice: whatever is in it is turned back on
/// at the next launch, so a crash does not leave applications hidden for good.
@available(macOS 27.0, *)
@MainActor
final class NativeAllowListConcealer27 {
    enum Failure: Error, CustomStringConvertible {
        case unavailable
        case unreadable
        case notSynchronized

        var description: String {
            switch self {
            case .unavailable: "The container-aware CoreFoundation preference calls are unavailable"
            case .unreadable: "MenuBarAgent's trackedApplications preference is missing or unreadable"
            case .notSynchronized: "The trackedApplications preference could not be synchronized"
            }
        }
    }

    private let logger = Logger(category: "NativeAllowListConcealer27")

    /// Whether the preference calls exist and MenuBarAgent's list can be read.
    static var isAvailable: Bool {
        Preferences.shared != nil && (try? Preferences.read()) != nil
    }

    /// Turns off the given applications that are tracked and allowed, and turns back on the ones
    /// Ice turned off earlier that are no longer among them.
    ///
    /// An application that is already off and that Ice did not turn off is the user's choice,
    /// and is left alone and not recorded. One that is not tracked yet — it has never created an
    /// item — cannot be turned off until MenuBarAgent adds it, so the caller applies again once
    /// it has had the chance; those are returned.
    @discardableResult
    func apply(concealed: Set<String>) throws -> Set<String> {
        var array = try Preferences.read()
        let states = TrackedApplications27.allowedStates(in: array)
        // What macOS keeps a switch for is not always what owns the item (see
        // `EnclosingApplication27`), so each identifier is looked up the way macOS files it.
        let switches = Dictionary(uniqueKeysWithValues: concealed.map {
            ($0, Self.switchIdentifier(for: $0, amongst: states))
        })
        let concealedSwitches = Set(switches.values)
        let recorded = Self.recorded
        let toDisallow = Set(concealedSwitches.filter { states[$0] == true })
        let toAllow = recorded.subtracting(concealedSwitches)
        // Recorded before the write: should Ice die between the two, the next launch turns these
        // back on, and every one of them was on a moment ago.
        Self.recorded = recorded.union(toDisallow)
        let disallowed = TrackedApplications27.settingAllowed(false, for: toDisallow, in: array)
        let allowed = TrackedApplications27.settingAllowed(true, for: toAllow, in: disallowed.array)
        array = allowed.array
        if !disallowed.changed.isEmpty || !allowed.changed.isEmpty {
            try Preferences.write(array)
            if !disallowed.changed.isEmpty {
                logger.notice("Disallowed in the menu bar: \(disallowed.changed.sorted().joined(separator: " "), privacy: .public)")
            }
            if !allowed.changed.isEmpty {
                logger.notice("Allowed in the menu bar again: \(allowed.changed.sorted().joined(separator: " "), privacy: .public)")
            }
        }
        // What stays recorded is what is concealed and still off. One the user turned back on in
        // System Settings meanwhile is turned off again above, since it is still meant to be
        // hidden; one MenuBarAgent forgot is no longer Ice's to restore.
        let final = TrackedApplications27.allowedStates(in: array)
        Self.recorded = Self.recorded.intersection(concealedSwitches).filter { final[$0] == false }
        // Answered in the identifiers the caller asked about, which is what it watches launching.
        return concealed.filter { states[switches[$0] ?? $0] == nil }
    }

    /// The identifier macOS keeps the menu bar switch under for the application that owns the
    /// item of the given identifier.
    ///
    /// Its own, when there is a switch for it. Otherwise the application its process lives
    /// inside: Docker Desktop's item comes from a helper within `Docker.app`, and the switch
    /// belongs to the application.
    private static func switchIdentifier(for bundleID: String, amongst states: [String: Bool]) -> String {
        guard states[bundleID] == nil else {
            return bundleID
        }
        guard
            let application = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
            let path = application.bundleURL?.path,
            let enclosing = EnclosingApplication27.outermostApplicationPath(of: path),
            let plist = NSDictionary(contentsOfFile: enclosing + "/Contents/Info.plist"),
            let enclosingID = plist["CFBundleIdentifier"] as? String,
            states[enclosingID] != nil
        else {
            return bundleID
        }
        return enclosingID
    }

    /// Turns back on every application Ice turned off, in this run or an earlier one.
    ///
    /// Called at launch, before anything else, and at termination. If the list cannot be read,
    /// the record is kept for the next attempt.
    func releaseAll() {
        let recorded = Self.recorded
        guard !recorded.isEmpty else {
            return
        }
        do {
            let array = try Preferences.read()
            let allowed = TrackedApplications27.settingAllowed(true, for: recorded, in: array)
            if !allowed.changed.isEmpty {
                try Preferences.write(allowed.array)
                logger.notice("Allowed in the menu bar again: \(allowed.changed.sorted().joined(separator: " "), privacy: .public)")
            }
            Self.recorded = []
        } catch {
            logger.error("Could not allow \(recorded.sorted().joined(separator: " "), privacy: .public) again: \(error, privacy: .public)")
        }
    }

    /// The applications Ice has turned off and not yet back on.
    private static var recorded: Set<String> {
        get { Set(Defaults.stringArray(forKey: .macOS27NativeDisallowed) ?? []) }
        set { Defaults.set(newValue.sorted(), forKey: .macOS27NativeDisallowed) }
    }
}

// MARK: - Preferences

@available(macOS 27.0, *)
extension NativeAllowListConcealer27 {
    /// CoreFoundation's container-aware preference calls, looked up at first use.
    ///
    /// They are private, so their absence is an answer rather than a crash: without them
    /// ``NativeAllowListConcealer27/isAvailable`` is false and the concealer uses assessment mode.
    private struct Preferences {
        typealias Copy = @convention(c) (CFString, CFString, CFString, CFString, CFString) -> Unmanaged<CFPropertyList>?
        typealias SetValue = @convention(c) (CFString, CFPropertyList?, CFString, CFString, CFString, CFString) -> Void
        typealias Synchronize = @convention(c) (CFString, CFString, CFString, CFString) -> Bool

        let copy: Copy
        let set: SetValue
        let synchronize: Synchronize

        static let shared: Preferences? = {
            guard
                let handle = dlopen("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation", RTLD_NOW),
                let copy = dlsym(handle, "_CFPreferencesCopyValueWithContainer"),
                let set = dlsym(handle, "_CFPreferencesSetValueWithContainer"),
                let synchronize = dlsym(handle, "_CFPreferencesSynchronizeWithContainer")
            else {
                return nil
            }
            return Preferences(
                copy: unsafeBitCast(copy, to: Copy.self),
                set: unsafeBitCast(set, to: SetValue.self),
                synchronize: unsafeBitCast(synchronize, to: Synchronize.self)
            )
        }()

        static let key = "trackedApplications" as CFString
        static let applicationID = "group.com.apple.controlcenter" as CFString

        static var container: CFString {
            (NSHomeDirectory() + "/Library/Group Containers/group.com.apple.controlcenter") as CFString
        }

        static func read() throws -> [Any] {
            guard let shared else {
                throw Failure.unavailable
            }
            guard
                let value = shared.copy(key, applicationID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost, container)?.takeRetainedValue(),
                let data = value as? Data,
                let array = TrackedApplications27.decode(data)
            else {
                throw Failure.unreadable
            }
            return array
        }

        static func write(_ array: [Any]) throws {
            guard let shared else {
                throw Failure.unavailable
            }
            let data = try TrackedApplications27.encode(array)
            shared.set(key, data as CFData, applicationID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost, container)
            guard shared.synchronize(applicationID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost, container) else {
                throw Failure.notSynchronized
            }
        }
    }
}
