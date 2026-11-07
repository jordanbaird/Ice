//
//  Swizzling.swift
//  Ice
//

import Cocoa

extension NSSplitViewItem {
    @nonobjc private static let swizzler: () = {
        let originalCanCollapseSel = #selector(getter: canCollapse)
        let swizzledCanCollapseSel = #selector(getter: swizzledCanCollapse)

        guard
            let originalCanCollapseMethod = class_getInstanceMethod(NSSplitViewItem.self, originalCanCollapseSel),
            let swizzledCanCollapseMethod = class_getInstanceMethod(NSSplitViewItem.self, swizzledCanCollapseSel)
        else {
            return
        }

        method_exchangeImplementations(originalCanCollapseMethod, swizzledCanCollapseMethod)
    }()

    // AppKit only asks this on the main thread; the isolation is checked at runtime.
    @MainActor @objc private var swizzledCanCollapse: Bool {
        if viewController.view.window?.identifier?.rawValue == IceWindowIdentifier.settings.rawValue {
            return false
        }
        return self.swizzledCanCollapse
    }

    static func swizzle() {
        _ = swizzler
    }
}
