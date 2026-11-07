//
//  SCKGeometry.swift
//  Ice
//

import CoreGraphics

/// Geometry for ScreenCaptureKit captures.
///
/// `SCDisplay.frame`, `SCWindow.frame` and the `screenBounds` used by the
/// CGWindowList API are in global display coordinates (origin at the top
/// left of the main display, y pointing down, negative for displays above
/// or to the left). `SCStreamConfiguration.sourceRect` is different: it is
/// in points in the *display's own* coordinate space, with its origin at
/// the display's top left corner.
enum SCKGeometry {
    /// Converts a global rectangle to a display-local `sourceRect` and the
    /// output size in pixels.
    ///
    /// - Returns: `nil` if the rectangle does not intersect the display or
    ///   is smaller than a point after clipping.
    static func sourceRect(
        forGlobalRect rect: CGRect,
        onDisplay displayFrame: CGRect,
        scale: CGFloat
    ) -> (rect: CGRect, pixelSize: CGSize)? {
        let clipped = rect.intersection(displayFrame)
        guard !clipped.isNull, clipped.width >= 1, clipped.height >= 1 else {
            return nil
        }
        let local = clipped.offsetBy(dx: -displayFrame.origin.x, dy: -displayFrame.origin.y)
        let pixelSize = CGSize(
            width: (local.width * scale).rounded(),
            height: (local.height * scale).rounded()
        )
        return (local, pixelSize)
    }
}
