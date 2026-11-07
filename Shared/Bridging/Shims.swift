//
//  Shims.swift
//  Shared
//

import ApplicationServices
import CoreGraphics

// MARK: - Bridged Types

typealias CGSConnectionID = Int32
typealias CGSSpaceID = Int

enum CGSSpaceType: UInt32 {
    case user = 0
    case system = 2
    case fullscreen = 4
}

struct CGSSpaceMask: OptionSet {
    let rawValue: UInt32

    static let includesCurrent = CGSSpaceMask(rawValue: 1 << 0)
    static let includesOthers = CGSSpaceMask(rawValue: 1 << 1)
    static let includesUser = CGSSpaceMask(rawValue: 1 << 2)

    static let visible = CGSSpaceMask(rawValue: 1 << 16)

    static let currentSpaceMask: CGSSpaceMask = [.includesUser, .includesCurrent]
    static let otherSpacesMask: CGSSpaceMask = [.includesOthers, .includesCurrent]
    static let allSpacesMask: CGSSpaceMask = [.includesUser, .includesOthers, .includesCurrent]
    static let allVisibleSpacesMask: CGSSpaceMask = [.visible, .allSpacesMask]
}

// MARK: - CGSConnection

@_silgen_name("CGSMainConnectionID")
func CGSMainConnectionID() -> CGSConnectionID

@_silgen_name("CGSDefaultConnectionForThread")
func CGSDefaultConnectionForThread() -> CGSConnectionID

@_silgen_name("CGSCopyConnectionProperty")
func CGSCopyConnectionProperty(
    _ cid: CGSConnectionID,
    _ targetCID: CGSConnectionID,
    _ key: CFString,
    _ outValue: inout Unmanaged<CFTypeRef>?
) -> CGError

@_silgen_name("CGSSetConnectionProperty")
func CGSSetConnectionProperty(
    _ cid: CGSConnectionID,
    _ targetCID: CGSConnectionID,
    _ key: CFString,
    _ value: CFTypeRef
) -> CGError

// MARK: - CGSDisplay

@_silgen_name("CGSCopyActiveMenuBarDisplayIdentifier")
func CGSCopyActiveMenuBarDisplayIdentifier(_ cid: CGSConnectionID) -> Unmanaged<CFString>?

// MARK: - CGSEvent

@_silgen_name("CGSEventIsAppUnresponsive")
func CGSEventIsAppUnresponsive(
    _ cid: CGSConnectionID,
    _ psn: inout ProcessSerialNumber
) -> Bool

@_silgen_name("CGSEventSetAppIsUnresponsiveNotificationTimeout")
func CGSEventSetAppIsUnresponsiveNotificationTimeout(
    _ cid: CGSConnectionID,
    _ timeout: Double
) -> CGError

// MARK: - CGSSpace

@_silgen_name("CGSGetActiveSpace")
func CGSGetActiveSpace(_ cid: CGSConnectionID) -> CGSSpaceID

@_silgen_name("CGSCopySpacesForWindows")
func CGSCopySpacesForWindows(
    _ cid: CGSConnectionID,
    _ mask: CGSSpaceMask,
    _ windowIDs: CFArray
) -> Unmanaged<CFArray>?

@_silgen_name("CGSManagedDisplayGetCurrentSpace")
func CGSManagedDisplayGetCurrentSpace(
    _ cid: CGSConnectionID,
    _ displayUUID: CFString
) -> CGSSpaceID

@_silgen_name("CGSSpaceGetType")
func CGSSpaceGetType(
    _ cid: CGSConnectionID,
    _ sid: CGSSpaceID
) -> CGSSpaceType

// MARK: - CGSWindow

@_silgen_name("CGSGetWindowCount")
func CGSGetWindowCount(
    _ cid: CGSConnectionID,
    _ targetCID: CGSConnectionID,
    _ outCount: inout Int32
) -> CGError

@_silgen_name("CGSGetOnScreenWindowCount")
func CGSGetOnScreenWindowCount(
    _ cid: CGSConnectionID,
    _ targetCID: CGSConnectionID,
    _ outCount: inout Int32
) -> CGError

@_silgen_name("CGSGetWindowList")
func CGSGetWindowList(
    _ cid: CGSConnectionID,
    _ targetCID: CGSConnectionID,
    _ count: Int32,
    _ list: UnsafeMutablePointer<CGWindowID>,
    _ outCount: inout Int32
) -> CGError

@_silgen_name("CGSGetOnScreenWindowList")
func CGSGetOnScreenWindowList(
    _ cid: CGSConnectionID,
    _ targetCID: CGSConnectionID,
    _ count: Int32,
    _ list: UnsafeMutablePointer<CGWindowID>,
    _ outCount: inout Int32
) -> CGError

@_silgen_name("CGSGetProcessMenuBarWindowList")
func CGSGetProcessMenuBarWindowList(
    _ cid: CGSConnectionID,
    _ targetCID: CGSConnectionID,
    _ count: Int32,
    _ list: UnsafeMutablePointer<CGWindowID>,
    _ outCount: inout Int32
) -> CGError

@_silgen_name("CGSGetScreenRectForWindow")
func CGSGetScreenRectForWindow(
    _ cid: CGSConnectionID,
    _ wid: CGWindowID,
    _ outRect: inout CGRect
) -> CGError

@_silgen_name("CGSGetWindowLevel")
func CGSGetWindowLevel(
    _ cid: CGSConnectionID,
    _ wid: CGWindowID,
    _ outLevel: inout CGWindowLevel
) -> CGError

// MARK: - ProcessSerialNumber

@_silgen_name("GetProcessForPID")
func GetProcessForPID(
    _ pid: pid_t,
    _ psn: inout ProcessSerialNumber
) -> OSStatus
