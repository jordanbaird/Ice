// Local fullscreen QA window; no status items, input taps or permission requests.
import AppKit

final class AppearanceFullscreenProbe: NSObject, NSApplicationDelegate {
    var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        menu.addItem(appItem)
        NSApp.mainMenu = menu
        window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 640, height: 400),
                          styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Ice Fullscreen QA"
        window.collectionBehavior = [.fullScreenPrimary]
        let button = NSButton(title: "Toggle Full Screen", target: window, action: #selector(NSWindow.toggleFullScreen(_:)))
        button.frame = CGRect(x: 180, y: 170, width: 280, height: 44)
        button.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
        window.contentView?.addSubview(button)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

let application = NSApplication.shared
let delegate = AppearanceFullscreenProbe()
application.setActivationPolicy(.regular)
application.delegate = delegate
application.run()
