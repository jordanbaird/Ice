// Read-only installed-app fullscreen QA; not part of the Ice target.
// Build: xcrun swiftc -parse-as-library Tests/AppearanceWindowAudit.swift -o <audit>
// Usage: <audit> [--watch <seconds: 1...30> <interval-ms: 20...1000>]
//
// Prints JSONL with exact Ice PID/build, every active display's native Space
// ID/type, and Ice-owned overlay window IDs/visibility/alpha/bounds. Type 4 is
// the fullscreen Space value used by Ice. The window inventory is diagnostic,
// not proof of composited pixels: take a menu-bar-only screenshot separately.
// No AX, capture session, input events, preferences, permissions request, app
// launch/quit, or window manipulation. Only the exact installed Ice app is
// accepted. Short watch mode can run alongside a manual fullscreen transition.

import AppKit

@_silgen_name("CGSMainConnectionID")
private func mainConnection() -> Int32
@_silgen_name("CGSGetActiveSpace")
private func activeSpace(_ connection: Int32) -> Int
@_silgen_name("CGSSpaceGetType")
private func spaceType(_ connection: Int32, _ space: Int) -> UInt32
@_silgen_name("CGSManagedDisplayGetCurrentSpace")
private func displaySpace(_ connection: Int32, _ uuid: CFString) -> Int

private enum AuditError: Error {
    case invalidArguments, installedAppUnavailable, windowListUnavailable
}

@main
private struct AppearanceWindowAudit {
    @MainActor
    static func main() {
        do {
            let arguments = Array(CommandLine.arguments.dropFirst())
            let duration: Double
            let interval: Double
            if arguments.isEmpty {
                duration = 0
                interval = 0
            } else if arguments.count == 3, arguments[0] == "--watch",
                      let seconds = Double(arguments[1]), seconds.isFinite, (1...30).contains(seconds),
                      let milliseconds = Double(arguments[2]), milliseconds.isFinite, (20...1000).contains(milliseconds) {
                duration = seconds
                interval = milliseconds / 1000
            } else {
                throw AuditError.invalidArguments
            }

            let application = try installedIce()
            let pid = application.processIdentifier
            let bundle = Bundle(url: application.bundleURL!)
            let connection = mainConnection()
            let started = ProcessInfo.processInfo.systemUptime
            repeat {
                guard try installedIce().processIdentifier == pid else {
                    throw AuditError.installedAppUnavailable
                }
                let sampleStarted = ProcessInfo.processInfo.systemUptime
                var snapshot = try snapshot(connection: connection, pid: pid)
                snapshot["unixTime"] = Date().timeIntervalSince1970
                snapshot["elapsedSeconds"] = sampleStarted - started
                snapshot["readMilliseconds"] = (ProcessInfo.processInfo.systemUptime - sampleStarted) * 1000
                snapshot["icePID"] = pid
                snapshot["iceBuild"] = bundle?.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
                snapshot["iceVersion"] = bundle?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
                let json = try JSONSerialization.data(withJSONObject: snapshot, options: [.sortedKeys])
                FileHandle.standardOutput.write(json)
                FileHandle.standardOutput.write(Data([10]))
                let remaining = duration - (ProcessInfo.processInfo.systemUptime - started)
                if duration == 0 || remaining <= 0 { break }
                Thread.sleep(forTimeInterval: min(interval, remaining))
            } while ProcessInfo.processInfo.systemUptime - started < duration
        } catch {
            let message = "Appearance audit failed: \(error). Usage: <audit> [--watch <seconds: 1...30> <interval-ms: 20...1000>]\n"
            FileHandle.standardError.write(Data(message.utf8))
            exit(1)
        }
    }

    @MainActor
    private static func installedIce() throws -> NSRunningApplication {
        let applications = NSRunningApplication.runningApplications(withBundleIdentifier: "com.jordanbaird.Ice")
        guard applications.count == 1, let application = applications.first,
              !application.isTerminated,
              application.bundleURL?.standardizedFileURL.path == "/Applications/Ice.app" else {
            throw AuditError.installedAppUnavailable
        }
        return application
    }

    @MainActor
    private static func snapshot(connection: Int32, pid: pid_t) throws -> [String: Any] {
        guard let windows = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] else {
            throw AuditError.windowListUnavailable
        }
        let currentSpace = activeSpace(connection)
        let screens: [[String: Any]] = NSScreen.screens.map { screen in
            let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            var record: [String: Any] = ["displayID": displayID, "frame": rectangle(screen.frame)]
            if let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue(),
               let text = CFUUIDCreateString(nil, uuid) {
                let space = displaySpace(connection, text)
                record["spaceID"] = space
                record["spaceType"] = spaceType(connection, space)
            }
            return record
        }
        let owned = windows.filter { ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid }
        let overlays = owned.filter { ($0[kCGWindowName as String] as? String) == "Menu Bar Overlay" }
        // Include only Ice's unnamed status-level windows so withheld window
        // names cannot silently turn an unknown overlay into an apparent pass.
        let unnamedStatusWindows = owned.filter {
            ($0[kCGWindowName as String] as? String) == nil &&
                ($0[kCGWindowLayer as String] as? NSNumber)?.intValue == Int(CGWindowLevelForKey(.statusWindow))
        }
        return [
            "activeSpaceID": currentSpace,
            "activeSpaceType": spaceType(connection, currentSpace),
            "displays": screens,
            "overlays": overlays.map(windowRecord),
            "unnamedIceStatusWindows": unnamedStatusWindows.map(windowRecord),
            "nativeMenuBars": windows.filter { ($0[kCGWindowName as String] as? String) == "Menubar" }.map(windowRecord),
        ]
    }

    private static func rectangle(_ rect: CGRect) -> [String: Double] {
        ["x": rect.minX, "y": rect.minY, "width": rect.width, "height": rect.height]
    }

    private static func windowRecord(_ window: [String: Any]) -> [String: Any] {
        [
            "id": window[kCGWindowNumber as String] ?? NSNull(),
            "onScreen": window[kCGWindowIsOnscreen as String] ?? NSNull(),
            "alpha": window[kCGWindowAlpha as String] ?? NSNull(),
            "layer": window[kCGWindowLayer as String] ?? NSNull(),
            "bounds": window[kCGWindowBounds as String] ?? NSNull(),
        ]
    }
}
