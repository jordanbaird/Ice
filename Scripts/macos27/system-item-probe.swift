// Holds an assessment-mode assertion with a chosen allowlist, so what MenuBarAgent keeps
// on the bar can be read off it one item at a time.
//
// The assertion only bites from a signed application bundle, so this file is built into
// one:
//
//   APP=/tmp/probe/Probe.app
//   mkdir -p "$APP/Contents/MacOS"
//   /usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string Probe" \
//       -c "Add :CFBundleIdentifier string com.jordanbaird.Ice.SystemItemProbe" \
//       -c "Add :CFBundlePackageType string APPL" -c "Add :LSUIElement bool true" \
//       "$APP/Contents/Info.plist"
//   swiftc -O Scripts/macos27/system-item-probe.swift -o "$APP/Contents/MacOS/Probe"
//   codesign --force --sign - "$APP"
//   "$APP/Contents/MacOS/Probe" --items 0,1,2 --apps com.foo.bar --seconds 3
//
// Quit Ice first: live assertions combine as a union of their allowlists, so Ice's own
// would answer for the items this one leaves out.
//
// Measured on macOS 27.0 with every number from 0 to 127 offered, one at a time
// (2026-09-29). MenuBarAgent accepts them all and draws five:
//
//     0  battery        2  clock        6  Wi-Fi        8  Control Centre
//     1, 3, 4, 5, 7, and everything from 9 up: nothing.
//
// Control Centre's capture indicator — the green camera button, orange for the
// microphone, indigo for screen sharing — is not among them. It is drawn while no
// assertion is live and disappears while one is, whatever the allowlist holds: all 128
// numbers, Control Centre's bundle identifier, the capturing application's bundle
// identifier. The small green dot beside the clock is not an item and stays either way.
import AppKit

func argument(_ flag: String) -> String? {
    let arguments = CommandLine.arguments
    guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
        return nil
    }
    return arguments[index + 1]
}

let itemNumbers = (argument("--items") ?? "").split(separator: ",").compactMap { Int($0) }
let bundleIDs = (argument("--apps") ?? "").split(separator: ",").map(String.init)
let seconds = Double(argument("--seconds") ?? "5") ?? 5

guard
    dlopen("/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore", RTLD_NOW) != nil,
    let configurationClass = NSClassFromString("MBAssessmentModeConfiguration"),
    let assertionClass = NSClassFromString("MBAssessmentModeAssertion")
else {
    print("MenuBarClientCore is unavailable")
    exit(1)
}

// An accessory application: a probe with a Dock icon would take the front from whatever
// is being watched.
NSApplication.shared.setActivationPolicy(.accessory)

guard
    let configuration = (configurationClass.alloc() as AnyObject).perform(
        NSSelectorFromString("initWithAllowedSystemItems:allowedBundleIdentifiers:"),
        with: itemNumbers.map { NSNumber(value: $0) } as NSArray,
        with: bundleIDs as NSArray
    )?.takeUnretainedValue(),
    let assertion = (assertionClass.alloc() as AnyObject)
        .perform(NSSelectorFromString("init"))?.takeUnretainedValue()
else {
    print("the assertion could not be built")
    exit(1)
}

let completion: @convention(block) (Any?) -> Void = { error in
    print("activate: \(error.map { String(describing: $0) } ?? "accepted")")
}
_ = assertion.perform(
    NSSelectorFromString("activateWithConfiguration:completionHandler:"),
    with: configuration,
    with: completion
)
RunLoop.main.run(until: Date().addingTimeInterval(seconds))
_ = assertion.perform(NSSelectorFromString("invalidate"))
print("done")
