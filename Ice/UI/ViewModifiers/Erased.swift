//
//  Erased.swift
//  Ice
//

import SwiftUI

extension View {
    /// Returns a view that has been erased to the `AnyView` type.
    func erased() -> AnyView {
        AnyView(erasing: self)
    }
}
