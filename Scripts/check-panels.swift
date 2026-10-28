//
//  check-panels.swift
//
//  Counts Ice's live windows, grouped by kind. Run with: swift check-panels.swift
//
//  Watches for the overlay-panel leak: those are the borderless, unnamed windows
//  as wide as a display and about as tall as a menu bar. There should be at most
//  one per display, and none at all unless the menu bar appearance uses a shape,
//  tint, border or shadow. More than one per display means they are accumulating,
//  which is what made expanding the menu bar fail after a few display changes.
//
import Cocoa

guard let pid = NSWorkspace.shared.runningApplications
        .first(where: { $0.bundleIdentifier == "com.jordanbaird.Ice" })?
        .processIdentifier,
      let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]]
else {
    print("Ice is not running")
    exit(0)
}

let barHeights: Set<Int> = Set(NSScreen.screens.map { Int(($0.frame.maxY - $0.visibleFrame.maxY).rounded()) })
var counts: [String: Int] = [:]
var overlayLike: [String: Int] = [:]

for window in list where (window[kCGWindowOwnerPID as String] as? pid_t) == pid {
    let bounds = window[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]
    let width = Int(bounds["Width"] ?? 0)
    let height = Int(bounds["Height"] ?? 0)
    let name = window[kCGWindowName as String] as? String ?? ""
    let key = name.isEmpty ? "<unnamed> \(width)x\(height)" : name
    counts[key, default: 0] += 1
    // An overlay panel spans a whole display and is roughly a menu bar tall.
    if name.isEmpty, height > 0, height <= 60,
       NSScreen.screens.contains(where: { Int($0.frame.width.rounded()) == width }) {
        overlayLike[key, default: 0] += 1
    }
    _ = barHeights
}

print("Ice pid \(pid), \(NSScreen.screens.count) display(s)")
for (key, count) in counts.sorted(by: { $0.value > $1.value }) {
    let leaking = (overlayLike[key] ?? 0) > 1
    print("  \(count)x  \(key)\(leaking ? "   <-- ACCUMULATING" : "")")
}

let worst = overlayLike.values.max() ?? 0
print(worst > 1
      ? "\nOverlay panels are accumulating: \(worst) copies of one panel."
      : "\nOverlay panels look healthy.")
