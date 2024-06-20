//
//  Deprecated.swift
//  Ice
//

import ApplicationServices
import CoreGraphics

/// Returns a composite image of the specified windows.
///
/// This function links to a deprecated CoreGraphics function. We link to it this way to
/// prevent a deprecation warning. If ScreenCaptureKit is ever able to capture offscreen
/// windows, this function can be removed.
///
/// See the documentation for the deprecated function here:
///
/// https://developer.apple.com/documentation/coregraphics/1455730-cgwindowlistcreateimagefromarray
@_silgen_name("CGWindowListCreateImageFromArray")
func CGWindowListCreateImageFromArray(
    _ screenBounds: CGRect,
    _ windowArray: CFArray,
    _ imageOption: CGWindowImageOption
) -> CGImage?

/// Returns a PSN for a given PID.
@_silgen_name("GetProcessForPID")
func GetProcessForPID(
    _ pid: pid_t,
    _ psn: inout ProcessSerialNumber
) -> OSStatus
