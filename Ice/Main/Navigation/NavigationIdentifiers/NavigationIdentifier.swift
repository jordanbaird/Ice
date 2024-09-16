//
//  NavigationIdentifier.swift
//  Ice
//

import SwiftUI

/// A type that represents an identifier used for navigation in a user interface.
protocol NavigationIdentifier: CaseIterable, Hashable, Identifiable, RawRepresentable {
    /// A localized description of the identifier that can be presented to the user.
    var localized: LocalizedStringKey { get }
}

extension NavigationIdentifier where ID == Int {
    var id: Int { hashValue }
}

extension NavigationIdentifier where RawValue == String {
    var localized: LocalizedStringKey { LocalizedStringKey(rawValue) }
}
