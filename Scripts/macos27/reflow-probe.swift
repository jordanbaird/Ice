// Throwaway probe: does a status item that appears, changes width and goes away make MenuBarAgent
// re-evaluate which items the notched built-in bar folds behind "<<"?
// usage: reflow-probe [mode]      mode: add-remove (default) | resize
import AppKit

let mode = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "add-remove"
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

func pause(_ seconds: TimeInterval) {
    RunLoop.main.run(until: Date().addingTimeInterval(seconds))
}

let item = NSStatusBar.system.statusItem(withLength: 40)
item.button?.title = "·"
pause(1.5)
if mode == "resize" {
    for length in [CGFloat(120), 1, 60, 1] {
        item.length = length
        pause(0.8)
    }
}
NSStatusBar.system.removeStatusItem(item)
pause(1.5)
print("probe \(mode): done")
