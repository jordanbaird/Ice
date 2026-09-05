// Manual timing diagnostic for Ice's own AXPress action only, not a test of
// hardware mouse tracking or a substitute for visual native-menu-bar QA.
// Run only after the user has unlocked the Mac. Never requests permissions,
// posts global input, moves status items, or changes app/system preferences.
// Usage: native-ice-toggle-probe <press-count: 1...20> <interval-ms: 50...1000>
import AppKit
import ApplicationServices

enum IceToggleProbeError: Error {
    case invalidArguments, permissionUnavailable, ambiguousApplication, missingButton, actionFailed(AXError)
}

private func attribute<T>(_ element: AXUIElement, _ key: String) -> T? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success else { return nil }
    return value as? T
}

private func iceButton(in root: AXUIElement) -> AXUIElement? {
    guard let extras: AXUIElement = attribute(root, kAXExtrasMenuBarAttribute),
          let children: [AXUIElement] = attribute(extras, kAXChildrenAttribute) else { return nil }
    return children.first { child in
        let identifier: String? = attribute(child, kAXIdentifierAttribute)
        return identifier == "Ice.ControlItem.Visible"
    }
}

@main
enum NativeIceToggleProbe {
    static func main() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.count == 2, let count = Int(arguments[0]), (1 ... 20).contains(count),
              let interval = Double(arguments[1]), interval.isFinite, (50 ... 1000).contains(interval) else {
            throw IceToggleProbeError.invalidArguments
        }
        guard AXIsProcessTrusted() else { throw IceToggleProbeError.permissionUnavailable }
        let applications = NSRunningApplication.runningApplications(withBundleIdentifier: "com.jordanbaird.Ice")
        guard applications.count == 1, let application = applications.first,
              application.bundleURL?.standardizedFileURL.path == "/Applications/Ice.app" else {
            throw IceToggleProbeError.ambiguousApplication
        }
        let root = AXUIElementCreateApplication(application.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.25)
        guard let button = iceButton(in: root) else { throw IceToggleProbeError.missingButton }
        let clock = ContinuousClock()
        let start = clock.now
        print("Ice PID \(application.processIdentifier), \(count) AX presses, requested interval \(interval) ms")
        print("These timestamps are action acknowledgements, NOT render/animation latency.")
        fflush(stdout)
        for index in 0 ..< count {
            guard !application.isTerminated,
                  attribute(button, kAXIdentifierAttribute) as String? == "Ice.ControlItem.Visible" else {
                throw IceToggleProbeError.missingButton
            }
            let actionStart = clock.now
            let result = AXUIElementPerformAction(button, kAXPressAction as CFString)
            guard result == .success else { throw IceToggleProbeError.actionFailed(result) }
            let label: String = attribute(button, kAXDescriptionAttribute) ?? "no description"
            print("press \(index + 1): elapsed=\(start.duration(to: clock.now)), action=\(actionStart.duration(to: clock.now)), label=\(label)")
            fflush(stdout)
            if index + 1 < count { Thread.sleep(forTimeInterval: interval / 1000) }
        }
        print("Observe the final physical menu bar; even counts should return to the initial state.")
        print("Do not infer physical visibility from the label alone.")
    }
}
