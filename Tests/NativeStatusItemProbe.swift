// Manual AppKit reproducer, not part of the Ice application target.
// Package as an .app and quit Ice first. Left 2 / Left 1 must be left of
// the blank boundary and Probe must be on its right. An isolated far-left
// oversized item does not test whether neighboring items can be hidden.
import AppKit

@MainActor
final class NativeStatusItemProbe: NSObject, NSApplicationDelegate {
    private var items = [NSStatusItem]()
    private var boundary: NSStatusItem!
    private var hidden = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        for name in ["Probe", "Boundary", "Left 1", "Left 2"] {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.autosaveName = "Ice.NativeWidthProbe.\(name)"
            item.button?.title = name == "Boundary" ? "" : name
            items.append(item)
            if name == "Boundary" { boundary = item }
            if name == "Probe" {
                item.button?.target = self
                item.button?.action = #selector(toggleWidth)
            }
        }
        print("Click Probe to toggle only its own blank boundary; clock and other items use native input.")
    }

    @objc private func toggleWidth() {
        hidden.toggle()
        if hidden {
            guard let screen = NSScreen.main else { return }
            let regionWidth = screen.auxiliaryTopRightArea?.width ?? (screen.frame.width - 300)
            // The optional argument demonstrates rejected oversized widths.
            boundary.length = CommandLine.arguments.dropFirst().first.flatMap(Double.init)
                .map(CGFloat.init) ?? max(32, regionWidth - 32)
            boundary.isVisible = true
        } else {
            let key = "NSStatusItem Preferred Position \(boundary.autosaveName ?? "")"
            let position = UserDefaults.standard.object(forKey: key)
            boundary.isVisible = false
            if let position { UserDefaults.standard.set(position, forKey: key) }
        }
        print("Hidden: \(hidden), requested boundary width: \(boundary.length)")
        fflush(stdout)
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = NativeStatusItemProbe()
    app.setActivationPolicy(.accessory)
    app.delegate = delegate
    app.run()
}
