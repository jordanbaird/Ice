//
//  ScreenCapture.swift
//  Ice
//

import CoreGraphics
import ScreenCaptureKit

/// A namespace for screen capture operations.
enum ScreenCapture {
    /// A cache for the permission verdict.
    ///
    /// Both signals this wraps are comparatively expensive (a TCC lookup and a
    /// window-server walk), and `Permission` polls on a 1 Hz main-actor timer,
    /// so the verdict is rate limited here rather than at every call site. There
    /// is deliberately only *one* cache: two disagreeing sources of truth let
    /// the UI say "Grant Permission" while the rest of the app believed it had
    /// access, which is the shape of bug #22.
    private enum PermissionProbe {
        /// How long a "not granted" verdict is trusted.
        ///
        /// Short, so a grant made in System Settings while Ice is running is
        /// noticed within a few seconds rather than needing a relaunch.
        static let denialTTL: TimeInterval = 2

        /// How long a "granted" verdict is trusted.
        ///
        /// Longer, because a grant is the expensive case to re-derive and
        /// nothing in the app needs it re-checked at 1 Hz. Kept finite so a
        /// revoked permission is still noticed.
        static let grantTTL: TimeInterval = 10

        /// Guards the cached verdict. The probe is reached from the main-actor
        /// permission timer and from background tasks alike.
        static let lock = NSLock()
        /// The last verdict, and when it was taken.
        static var cached: (granted: Bool, date: Date)?

        /// Returns the permission verdict, refreshing it when it is stale.
        ///
        /// - Parameter forceRefresh: Whether to ignore the cached verdict.
        static func granted(forceRefresh: Bool) -> Bool {
            lock.lock()
            if !forceRefresh, let cached {
                let ttl = cached.granted ? grantTTL : denialTTL
                if Date().timeIntervalSince(cached.date) < ttl {
                    lock.unlock()
                    return cached.granted
                }
            }
            lock.unlock()

            // Checked outside the lock: this talks to TCC and the window server.
            let startedAt = Date()
            let granted = checkNow()

            lock.lock()
            defer { lock.unlock() }
            // A slow check must not overwrite a fresher one.
            if let current = cached, current.date > startedAt {
                return current.granted
            }
            cached = (granted, startedAt)
            return granted
        }
    }

    /// Runs the permission check without consulting the cache.
    ///
    /// The layers are positive-only: each can *confirm* that the permission was
    /// granted, and none may report a denial on its own. A wrong "denied"
    /// verdict is what made the app re-prompt for a permission the user had
    /// already granted (issue #22), so the checks run from authoritative to
    /// heuristic and no heuristic is allowed to deny.
    private static func checkNow() -> Bool {
        // Apple's own check is authoritative and never prompts. It is also the
        // expensive one, which is why the whole verdict is rate limited.
        if CGPreflightScreenCaptureAccess() {
            return true
        }
        return hasNamedForeignStatusItemWindow()
    }

    /// Returns a Boolean value that indicates whether the app has been granted screen capture permissions.
    ///
    /// - Parameter forceRefresh: Whether to bypass the cached verdict.
    static func checkPermissions(forceRefresh: Bool = false) -> Bool {
        PermissionProbe.granted(forceRefresh: forceRefresh)
    }

    /// Returns a Boolean value that indicates whether the window server is
    /// vending window names for a menu bar item, which it only does to
    /// processes with screen capture access.
    ///
    /// This is the live half of the check: `CGPreflightScreenCaptureAccess()`
    /// reports the value captured when the process launched, so it never
    /// notices a grant made while Ice is running, whereas a name lookup always
    /// reflects the permission as it is now.
    ///
    /// This reads the public `CGWindowList` rather than going through
    /// ``MenuBarItem/getMenuBarItems(onScreenOnly:activeSpaceOnly:)``, which is
    /// built on `CGSGetProcessMenuBarWindowList`. On macOS 27 that list vends
    /// only the `Menubar` window (layer 24) and no status items at all, so a
    /// scan built on it had nothing to inspect and every check silently fell
    /// through to the frozen preflight result.
    private static func hasNamedForeignStatusItemWindow() -> Bool {
        // `.optionAll`, not `.optionOnScreenOnly`: status windows come back
        // without a `kCGWindowIsOnscreen` key, so the on-screen filter drops
        // every one of them — measured on macOS 27, the on-screen variant
        // reports 0 status windows while `.optionAll` reports 6.
        guard
            let windows = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[CFString: Any]]
        else {
            return false
        }
        var statusWindows = 0
        for window in windows {
            guard let layer = window[kCGWindowLayer] as? Int, layer == kCGStatusWindowLevel else {
                continue
            }
            statusWindows += 1
            guard let name = window[kCGWindowName] as? String, !name.isEmpty else {
                continue
            }
            // The window server's own status pill is named whether or not we
            // hold the permission, so it is not evidence of anything.
            if (window[kCGWindowOwnerName] as? String) == "Window Server" {
                continue
            }
            // Our own item is not evidence either. Treating it as such would let
            // the app report "granted" with no permission at all and quietly
            // produce empty captures, which is worse than the bug being fixed.
            if let pid = window[kCGWindowOwnerPID] as? pid_t, pid == ProcessInfo.processInfo.processIdentifier {
                continue
            }
            logger.debug("Screen capture permission confirmed by the menu bar window \"\(name)\".")
            return true
        }
        logger.debug("No named menu bar window found; inspected \(statusWindows) status window(s).")
        return false
    }

    /// Returns a Boolean value that indicates whether the app has been granted screen capture permissions.
    ///
    /// Equivalent to ``checkPermissions(forceRefresh:)`` with the rate limiting
    /// described there. Denials are deliberately not cached for long: caching
    /// one for the life of the process is what left the app showing "Grant
    /// Permission" for a permission the user had already given.
    static func cachedCheckPermissions(reset: Bool = false) -> Bool {
        checkPermissions(forceRefresh: reset)
    }

    /// Requests screen capture permissions.
    ///
    /// Asking the system for a permission that has already been granted shows
    /// the prompt again (see issue #22), so this is a no-op once access is
    /// known. The settings pane is still opened by the caller.
    static func requestPermissions() {
        if checkPermissions(forceRefresh: true) {
            logger.info("Screen capture permission already granted; skipping request.")
            return
        }
        if #available(macOS 15.0, *) {
            // CGRequestScreenCaptureAccess() is broken on macOS 15. SCShareableContent requires
            // screen capture permissions, and triggers a request if the user doesn't have them.
            SCShareableContent.getWithCompletionHandler { _, error in
                if let error {
                    logger.error("Screen capture request failed: \(error.localizedDescription)")
                }
            }
        } else {
            CGRequestScreenCaptureAccess()
        }
    }

    /// Captures a composite image of an array of windows.
    ///
    /// - Parameters:
    ///   - windowIDs: The identifiers of the windows to capture.
    ///   - screenBounds: The bounds to capture. Pass `nil` to capture the minimum rectangle that encloses the windows.
    ///   - option: Options that specify the image to be captured.
    static func captureWindows(_ windowIDs: [CGWindowID], screenBounds: CGRect? = nil, option: CGWindowImageOption = []) -> CGImage? {
        let pointer = UnsafeMutablePointer<UnsafeRawPointer?>.allocate(capacity: windowIDs.count)
        for (index, windowID) in windowIDs.enumerated() {
            pointer[index] = UnsafeRawPointer(bitPattern: UInt(windowID))
        }
        guard let windowArray = CFArrayCreate(kCFAllocatorDefault, pointer, windowIDs.count, nil) else {
            return nil
        }
        return .windowListImage(from: screenBounds ?? .null, windowArray: windowArray, imageOption: option)
    }

    /// Captures an image of a window.
    ///
    /// - Parameters:
    ///   - windowID: The identifier of the window to capture.
    ///   - screenBounds: The bounds to capture. Pass `nil` to capture the minimum rectangle that encloses the window.
    ///   - option: Options that specify the image to be captured.
    static func captureWindow(_ windowID: CGWindowID, screenBounds: CGRect? = nil, option: CGWindowImageOption = []) -> CGImage? {
        captureWindows([windowID], screenBounds: screenBounds, option: option)
    }
}

/// A protocol used to suppress deprecation warnings for the `CGWindowList` screen capture APIs.
///
/// ScreenCaptureKit doesn't support capturing composite images of offscreen menu bar items, but
/// this should be replaced once it does.
private protocol WindowListImage {
    init?(windowListFromArrayScreenBounds: CGRect, windowArray: CFArray, imageOption: CGWindowImageOption)
}

private extension WindowListImage {
    static func windowListImage(from screenBounds: CGRect, windowArray: CFArray, imageOption: CGWindowImageOption) -> Self? {
        Self(windowListFromArrayScreenBounds: screenBounds, windowArray: windowArray, imageOption: imageOption)
    }
}

extension CGImage: WindowListImage { }

// MARK: - Logger
private extension ScreenCapture {
    static let logger = Logger(category: "ScreenCapture")
}
