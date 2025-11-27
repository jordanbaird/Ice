//
//  IceBarAutoEnableMode.swift
//  Ice
//
//  See: https://github.com/jordanbaird/Ice/pull/795

import SwiftUI

/// Detection modes for automatic Ice Bar enabling.
enum IceBarAutoEnableMode: Int, CaseIterable, Identifiable {
    /// Enable Ice Bar when screen width is below a threshold.
    case screenWidth = 0

    /// Enable Ice Bar only on screens with a notch.
    case screensWithNotch = 1

    var id: Int { rawValue }

    /// Localized string key representation.
    var localized: LocalizedStringKey {
        switch self {
        case .screenWidth: "Screen width threshold"
        case .screensWithNotch: "Screens with a notch"
        }
    }
}
