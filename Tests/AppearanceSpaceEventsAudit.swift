// Read-only 20-second workspace notification audit; not part of the Ice target.
// Build: swiftc -parse-as-library Tests/AppearanceSpaceEventsAudit.swift -o <audit>
// Records only startup, native activeSpaceDidChangeNotification, and shutdown.
// No polling, AX, input, captures, permissions, windows or application mutations.
// Uses NSApplication's event loop with prohibited activation; a bare CLI run
// loop does not establish whether a normal AppKit app receives the notification.

import AppKit

@_silgen_name("CGSMainConnectionID")
private func mainConnection() -> Int32
@_silgen_name("CGSGetActiveSpace")
private func activeSpace(_ connection: Int32) -> Int
@_silgen_name("CGSSpaceGetType")
private func spaceType(_ connection: Int32, _ space: Int) -> UInt32
@_silgen_name("CGSManagedDisplayGetCurrentSpace")
private func displaySpace(_ connection: Int32, _ uuid: CFString) -> Int

@main
private struct AppearanceSpaceEventsAudit {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.prohibited)
        let connection = mainConnection()
        let started = ProcessInfo.processInfo.systemUptime
        let center = NSWorkspace.shared.notificationCenter
        let observer = center.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                record(reason: "activeSpaceDidChange", connection: connection, started: started)
            }
        }
        let deadline = Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { _ in
            MainActor.assumeIsolated {
                record(reason: "finished", connection: connection, started: started)
                application.terminate(nil)
            }
        }
        record(reason: "started", connection: connection, started: started)
        withExtendedLifetime((deadline, observer)) {
            application.run()
        }
        center.removeObserver(observer)
    }

    @MainActor
    private static func record(reason: String, connection: Int32, started: TimeInterval) {
        let active = activeSpace(connection)
        let displays: [[String: Any]] = NSScreen.screens.map { screen in
            let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            var record: [String: Any] = ["displayID": displayID]
            if let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue(),
               let text = CFUUIDCreateString(nil, uuid) {
                let space = displaySpace(connection, text)
                record["spaceID"] = space
                record["spaceType"] = spaceType(connection, space)
            }
            return record
        }
        let record: [String: Any] = [
            "event": reason,
            "eventLoop": "NSApplication.prohibited",
            "unixTime": Date().timeIntervalSince1970,
            "elapsedSeconds": ProcessInfo.processInfo.systemUptime - started,
            "activeSpaceID": active,
            "activeSpaceType": spaceType(connection, active),
            "displays": displays,
        ]
        do {
            let data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data([10]))
        } catch {
            FileHandle.standardError.write(Data("Cannot encode Space event: \(error)\n".utf8))
        }
    }
}
