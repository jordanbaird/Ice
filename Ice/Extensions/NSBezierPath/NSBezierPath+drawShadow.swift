//
//  NSBezierPath+drawShadow.swift
//  Ice
//

import Cocoa

extension NSBezierPath {
    func drawShadow(color: NSColor, radius: CGFloat) {
        guard let context = NSGraphicsContext.current else {
            return
        }

        let bounds = bounds.insetBy(dx: -radius, dy: -radius)

        let shadow = NSShadow()
        shadow.shadowBlurRadius = radius
        shadow.shadowColor = color

        // swiftlint:disable:next force_cast
        let path = copy() as! NSBezierPath

        context.saveGraphicsState()

        shadow.set()
        NSColor.black.set()
        bounds.clip()
        path.fill()

        context.restoreGraphicsState()
    }
}
