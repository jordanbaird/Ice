// Read-only installed-build audit. Compile with xcrun swiftc and run while Ice
// is idle (outside Layout). This does not install taps or synthesize input.
import AppKit
import CoreGraphics

let processes = NSRunningApplication.runningApplications(withBundleIdentifier: "com.jordanbaird.Ice")
guard processes.count == 1, let process = processes.first else {
    fatalError("Expected exactly one installed Ice process")
}
var count: UInt32 = 0
guard CGGetEventTapList(0, nil, &count) == .success else {
    fatalError("Cannot enumerate event taps")
}
var taps = [CGEventTapInformation](repeating: CGEventTapInformation(), count: Int(count))
guard CGGetEventTapList(count, &taps, &count) == .success else {
    fatalError("Cannot read event taps")
}
let ownTaps = taps.prefix(Int(count)).filter { $0.tappingProcess == process.processIdentifier }
print("Ice PID: \(process.processIdentifier), bundle: \(process.bundleURL?.path ?? "unknown")")
print("Ice-owned event taps: \(ownTaps.count)")
precondition(ownTaps.isEmpty, "Native-only interaction must not install global input taps")
