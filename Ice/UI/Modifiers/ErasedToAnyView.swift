//
//  ErasedToAnyView.swift
//  Ice
//

import SwiftUI

extension View {
    /// Returns a view that has been erased to the `AnyView` type.
    func erasedToAnyView() -> AnyView {
        AnyView(erasing: self)
    }
}
