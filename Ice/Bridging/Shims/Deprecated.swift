//
//  Deprecated.swift
//  Ice
//

import ApplicationServices

/// Returns a PSN for a given PID.
@_silgen_name("GetProcessForPID")
func GetProcessForPID(
    _ pid: pid_t,
    _ psn: inout ProcessSerialNumber
) -> OSStatus
