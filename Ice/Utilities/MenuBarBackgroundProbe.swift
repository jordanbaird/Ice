//
//  MenuBarBackgroundProbe.swift
//  Ice
//

import AppKit
import Combine
import Foundation

/// Detects system settings that conflict with backdrop mode.
///
/// - `isOpaqueBackgroundEnabled` reflects macOS's "Show menu bar background"
///   option, read via SkyLight's `SLSGetMenuBarUseBlurredAppearance` (private
///   SPI, since the setting isn't exposed as a documented `UserDefaults`
///   key). Polled because the matching SkyLight notification isn't trivial to
///   bridge to Swift.
/// - `isReduceTransparencyEnabled` reflects Accessibility → Display → Reduce
///   transparency, observed via `NSWorkspace`.
///
/// If the private symbol lookup fails (e.g. on a future macOS where the SPI
/// is renamed), the opaque-background flag simply reports `false` and the
/// dependent UI hides itself.
@MainActor
final class MenuBarBackgroundProbe: ObservableObject {
    @Published private(set) var isOpaqueBackgroundEnabled: Bool = false
    @Published private(set) var isReduceTransparencyEnabled: Bool = false

    private var timer: Timer?
    private var observer: NSObjectProtocol?

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshOpaqueBackground() }
        }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshReduceTransparency() }
        }
    }

    deinit {
        timer?.invalidate()
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    func refresh() {
        refreshOpaqueBackground()
        refreshReduceTransparency()
    }

    private func refreshOpaqueBackground() {
        isOpaqueBackgroundEnabled = SkyLightMenuBarSPI.isBlurredAppearanceEnabled ?? false
    }

    private func refreshReduceTransparency() {
        isReduceTransparencyEnabled = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }
}

// MARK: - SkyLight SPI

private enum SkyLightMenuBarSPI {
    private typealias MainConnectionIDFn = @convention(c) () -> Int32
    private typealias GetUseBlurredAppearanceFn = @convention(c) (Int32) -> Bool

    private static let handle: UnsafeMutableRawPointer? = {
        dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
    }()

    private static let mainConnectionID: MainConnectionIDFn? = {
        guard let handle, let sym = dlsym(handle, "SLSMainConnectionID") else { return nil }
        return unsafeBitCast(sym, to: MainConnectionIDFn.self)
    }()

    private static let getUseBlurredAppearance: GetUseBlurredAppearanceFn? = {
        guard let handle, let sym = dlsym(handle, "SLSGetMenuBarUseBlurredAppearance") else { return nil }
        return unsafeBitCast(sym, to: GetUseBlurredAppearanceFn.self)
    }()

    /// Whether the menu bar is currently drawn with its blurred/opaque
    /// material — i.e. macOS's "Show menu bar background" is on. Returns
    /// `nil` if the SPI couldn't be resolved.
    static var isBlurredAppearanceEnabled: Bool? {
        guard let getUseBlurredAppearance, let mainConnectionID else {
            return nil
        }
        return getUseBlurredAppearance(mainConnectionID())
    }
}
