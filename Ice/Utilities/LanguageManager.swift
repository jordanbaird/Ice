import SwiftUI

@MainActor
final class LanguageManager: NSObject {
    static let shared = LanguageManager()

    func makeMenuItem() -> NSMenuItem {
        let title = String(localized: "Language")
        let submenu = NSMenu(title: title)
        for language in AppLanguage.allCases {
            let item = NSMenuItem(
                title: language.displayName,
                action: #selector(selectLanguage),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = language.rawValue
            item.state = language == AppLanguage.current() ? .on : .off
            submenu.addItem(item)
        }
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        guard
            let identifier = sender.representedObject as? String,
            let language = AppLanguage(rawValue: identifier)
        else {
            return
        }
        requestChange(to: language)
    }

    func requestChange(to language: AppLanguage) {
        guard language != AppLanguage.current() else {
            return
        }
        let alert = NSAlert()
        alert.messageText = String(localized: "Restart Ice to change language?")
        alert.informativeText = String(localized: "Ice will restart to use the selected language. Your other settings will be preserved.")
        alert.addButton(withTitle: String(localized: "Restart Now"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        restart {
            language.save()
        }
    }

    func completeInitialSetup(with language: AppLanguage) {
        if language == AppLanguage.current() {
            language.save()
            UserDefaults.standard.set(true, forKey: AppLanguage.setupCompletedKey)
        } else {
            restart {
                language.save()
                UserDefaults.standard.set(true, forKey: AppLanguage.setupCompletedKey)
            }
        }
    }

    func restart(beforeTermination: () -> Void = {}) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        // 等旧进程退出后再启动；路径作为参数传递，避免空格和引号问题。
        process.arguments = [
            "-c",
            """
            count=0
            while kill -0 "$1" 2>/dev/null; do
                count=$((count + 1))
                [ "$count" -lt 100 ] || exit 1
                sleep 0.1
            done
            exec /usr/bin/open -n "$2"
            """,
            "ice-relaunch",
            String(ProcessInfo.processInfo.processIdentifier),
            Bundle.main.bundleURL.path,
        ]
        do {
            try process.run()
            beforeTermination()
            // 确保新进程能读到本次选择。
            UserDefaults.standard.synchronize()
            NSApp.terminate(nil)
        } catch {
            let errorAlert = NSAlert()
            errorAlert.messageText = String(localized: "Unable to restart Ice")
            errorAlert.informativeText = String(localized: "Please quit and reopen Ice manually.")
            errorAlert.addButton(withTitle: String(localized: "OK"))
            errorAlert.runModal()
        }
    }
}

struct LanguagePicker: View {
    @State private var language = AppLanguage.current()

    var body: some View {
        IcePicker("Language", selection: $language) {
            ForEach(AppLanguage.allCases) { language in
                Text(verbatim: language.displayName).tag(language)
            }
        }
        .onChange(of: language) { _, newValue in
            LanguageManager.shared.requestChange(to: newValue)
            language = AppLanguage.current()
        }
    }
}
