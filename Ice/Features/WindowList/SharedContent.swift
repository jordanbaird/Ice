//
//  SharedContent.swift
//  Ice
//

import Combine
import OSLog
import ScreenCaptureKit

class SharedContent {
    static var current: SharedContent {
        let current = SharedContent()
        let semaphore = DispatchSemaphore(value: 0)
        SCShareableContent.getWithCompletionHandler { content, error in
            defer {
                semaphore.signal()
            }
            guard let content else {
                return
            }
            current._windows = content.windows
            current._displays = content.displays
            current._applications = content.applications
            if let error {
                Logger.sharedContent.error("Error retrieving shared content: \(error)")
            }
        }
        switch semaphore.wait(timeout: .now() + 1) {
        case .success:
            return current
        case .timedOut:
            Logger.sharedContent.error("Error retrieving shared content: Timed out")
            return current
        }
    }

    private var _windows = [SCWindow]()
    private var _displays = [SCDisplay]()
    private var _applications = [SCRunningApplication]()

    var windows: [SCWindow] { _windows }
    var displays: [SCDisplay] { _displays }
    var applications: [SCRunningApplication] { _applications }

    private init() { }

    func firstWindow(where predicate: WindowPredicate) -> SCWindow? {
        windows.first(where: predicate.body)
    }
}

//extension SharedContent {
//    struct ContentType<Content> {
//        static var window: ContentType<SCWindow> { .init() }
//        static var display: ContentType<SCDisplay> { .init() }
//        static var application: ContentType<SCRunningApplication> { .init() }
//
//        private init() { }
//    }
//}

extension SharedContent {
    struct WindowPredicate {
        let body: (SCWindow) -> Bool

        static let isMenuBarWindow = WindowPredicate { window in
            // menu bar window belongs to the WindowServer process
            // (identified by an empty string)
            window.owningApplication?.bundleIdentifier == "" &&
            window.windowLayer == kCGMainMenuWindowLevel &&
            window.title == "Menubar"
        }

        static let isWallpaperWindow = WindowPredicate { window in
            // wallpaper window belongs to the Dock process
            window.owningApplication?.bundleIdentifier == "com.apple.dock" &&
            window.isOnScreen &&
            window.title?.hasPrefix("Wallpaper-") == true
        }
    }
}

// MARK: - Logger
private extension Logger {
    static let sharedContent = Logger.mainSubsystem(category: "SharedContent")
}
