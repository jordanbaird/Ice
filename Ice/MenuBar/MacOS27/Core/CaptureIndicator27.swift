//
//  CaptureIndicator27.swift
//  Ice
//

import CoreGraphics

/// Where Ice's own camera and microphone indicator goes, and which one it is.
///
/// macOS draws one of its own — the green camera button, orange for the microphone — but it is
/// Control Centre's, and Control Centre's modules are not items any allowlist can spare: while
/// an assessment assertion is live they are not drawn at all, whatever it allows (measured on
/// macOS 27.0 against every system item number up to 127, Control Centre's own bundle identifier
/// and the capturing application's). So while Ice hides anything, the user loses the one piece of
/// the menu bar that says their camera is on. Ice draws it back.
enum CaptureIndicator27 {
    /// What the indicator says.
    enum Kind: Equatable {
        /// The camera is in use, by this application or another.
        case camera
        /// The microphone is in use and the camera is not.
        case microphone
    }

    /// The indicator to show for the devices in use, or `nil` when there is nothing to say.
    ///
    /// The camera wins: macOS's own indicator shows the camera while both are running, and a
    /// camera in use is the thing a person wants to be sure of.
    static func kind(cameraInUse: Bool, microphoneInUse: Bool) -> Kind? {
        if cameraInUse {
            return .camera
        }
        return microphoneInUse ? .microphone : nil
    }

    /// Where to draw the indicator on a menu bar.
    ///
    /// Just left of the leftmost item the bar draws, so it sits where the items do rather than
    /// over the application menus, and moves with them as they come and go. Without an item to go
    /// by — a bar holding nothing but the system group — it keeps to the right end instead.
    ///
    /// - Parameters:
    ///   - barFrame: The menu bar's own frame, in screen coordinates.
    ///   - leftEdgeOfItems: The left edge of the leftmost item drawn on that bar.
    ///   - width: How wide to draw the indicator.
    ///   - gap: How much room to leave between it and the items.
    static func frame(
        barFrame: CGRect,
        leftEdgeOfItems: CGFloat?,
        width: CGFloat,
        gap: CGFloat
    ) -> CGRect {
        let right = (leftEdgeOfItems ?? barFrame.maxX) - gap
        let x = max(barFrame.minX, right - width)
        return CGRect(x: x, y: barFrame.minY, width: width, height: barFrame.height)
    }
}
