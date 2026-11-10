// Watches how quickly MenuBarAgent and Notification Center answer, and reports every moment
// they stall. Run it in the background while using the menu bar: a stall that lines up with a
// panel opening or closing says the stutter is in those processes rather than in the drawing.
//
// usage: agent-latency [spike-ms]        (default 25; prints every sample above it)
import AppKit
import ApplicationServices

let threshold = (CommandLine.arguments.count > 1 ? Double(CommandLine.arguments[1]) : nil) ?? 25

func element(of bundleID: String) -> (name: String, element: AXUIElement)? {
    guard let application = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
        return nil
    }
    let element = AXUIElementCreateApplication(application.processIdentifier)
    AXUIElementSetMessagingTimeout(element, 5)
    return (application.localizedName ?? bundleID, element)
}

let watched = ["com.apple.MenuBarAgent", "com.apple.notificationcenterui", "com.apple.controlcenter"]
    .compactMap(element(of:))
guard !watched.isEmpty else {
    print("none of the watched processes are running")
    exit(2)
}
print("watching " + watched.map(\.name).joined(separator: ", ") + ", reporting anything over \(Int(threshold)) ms")

let formatter = DateFormatter()
formatter.dateFormat = "HH:mm:ss.SSS"

/// Asks one question and returns how long the answer took.
func latency(_ element: AXUIElement) -> Double {
    let start = Date()
    var value: CFTypeRef?
    _ = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value)
    return Date().timeIntervalSince(start) * 1000
}

var samples = 0
var spikes = 0
while true {
    for (name, element) in watched {
        let milliseconds = latency(element)
        samples += 1
        if milliseconds > threshold {
            spikes += 1
            print(String(format: "%@  %@ stalled %.0f ms", formatter.string(from: Date()), name, milliseconds))
            fflush(stdout)
        }
    }
    usleep(20_000)
}
