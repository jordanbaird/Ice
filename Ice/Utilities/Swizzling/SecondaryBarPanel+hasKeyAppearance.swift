//
//  SecondaryBarPanel+hasKeyAppearance.swift
//  Ice
//

import Cocoa

extension SecondaryBarPanel {
    @nonobjc private static let swizzler: () = {
        let originalCanCollapseSel = NSSelectorFromString("hasKeyAppearance")
        let swizzledCanCollapseSel = #selector(getter: swizzledHasKeyAppearance)

        guard
            let originalCanCollapseMethod = class_getInstanceMethod(SecondaryBarPanel.self, originalCanCollapseSel),
            let swizzledCanCollapseMethod = class_getInstanceMethod(SecondaryBarPanel.self, swizzledCanCollapseSel)
        else {
            return
        }

        method_exchangeImplementations(originalCanCollapseMethod, swizzledCanCollapseMethod)
    }()

    @objc private var swizzledHasKeyAppearance: Bool {
        return true
    }

    static func swizzle() {
        _ = swizzler
    }
}
