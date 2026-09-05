// Isolated dynamic-status-item QA host. It owns one unidentified NSStatusItem
// and a control window; no event taps, captures, permission prompts or defaults.
import AppKit

@MainActor
final class DynamicStatusItemProbe: NSObject, NSApplicationDelegate {
    private var item: NSStatusItem?
    private var window: NSWindow!
    private let state = NSTextField(labelWithString: "")
    private var revision = 1

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(
            contentRect: NSRect(x: 300, y: 300, width: 420, height: 190),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Ice Dynamic Item Probe"
        let explanation = NSTextField(wrappingLabelWithString:
            "Rename changes the same status item. Withdraw removes the last item while this app stays running. Restore publishes a new item."
        )
        let controls = NSStackView(views: [
            button("Rename", action: #selector(rename)),
            button("Withdraw", action: #selector(withdraw)),
            button("Restore", action: #selector(restore)),
            button("Quit", action: #selector(quit)),
        ])
        controls.orientation = .horizontal
        controls.spacing = 8
        let stack = NSStackView(views: [explanation, state, controls])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView?.addSubview(stack)
        if let content = window.contentView {
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
                stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
                stack.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            ])
        }
        restore()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func button(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        return button
    }

    @objc private func rename() {
        revision += 1
        if let button = item?.button {
            button.title = "Dyn \(revision)"
            button.setAccessibilityLabel("Dynamic \(revision)")
        }
        updateState()
    }

    @objc private func withdraw() {
        if let item { NSStatusBar.system.removeStatusItem(item) }
        item = nil
        updateState()
    }

    @objc private func restore() {
        guard item == nil else { return }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item?.button?.title = "Dyn \(revision)"
        item?.button?.setAccessibilityLabel("Dynamic \(revision)")
        updateState()
    }

    private func updateState() {
        state.stringValue = item == nil ? "Withdrawn; host still running" : "Published: Dynamic \(revision)"
        print(state.stringValue)
    }

    @objc private func quit() { NSApp.terminate(nil) }

    func applicationWillTerminate(_ notification: Notification) {
        if let item { NSStatusBar.system.removeStatusItem(item) }
    }
}

@main
enum DynamicStatusItemProbeMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = DynamicStatusItemProbe()
        app.setActivationPolicy(.regular)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
