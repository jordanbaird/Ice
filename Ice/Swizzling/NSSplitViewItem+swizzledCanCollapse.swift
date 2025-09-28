//
//  NSSplitViewItem+swizzledCanCollapse.swift
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

    @objc private var swizzledCanCollapse: Bool {
        if
            let window = viewController.view.window,
            window.identifier?.rawValue == Constants.settingsWindowID
        {
            return false
        }
        return self.swizzledCanCollapse
    }

    static func swizzle() {
        if #available(macOS 26, *) {
            // Workaround: disable swizzle on macOS 26+ to avoid crash; minor UI issue is acceptable.
            return
        }
        _ = swizzler
    }
}
