//
//  IceBarPanel+hasKeyAppearance.swift
//  Ice
//

import Cocoa

extension IceBarPanel {
    @nonobjc private static let swizzler: () = {
        let originalHasKeyAppearanceSel = NSSelectorFromString("hasKeyAppearance")
        let swizzledHasKeyAppearanceSel = #selector(getter: swizzledHasKeyAppearance)

        guard
            let originalHasKeyAppearanceMethod = class_getInstanceMethod(IceBarPanel.self, originalHasKeyAppearanceSel),
            let swizzledHasKeyAppearanceMethod = class_getInstanceMethod(IceBarPanel.self, swizzledHasKeyAppearanceSel)
        else {
            return
        }

        method_exchangeImplementations(originalHasKeyAppearanceMethod, swizzledHasKeyAppearanceMethod)
    }()

    @objc private var swizzledHasKeyAppearance: Bool {
        return true
    }

    static func swizzle() {
        _ = swizzler
    }
}
