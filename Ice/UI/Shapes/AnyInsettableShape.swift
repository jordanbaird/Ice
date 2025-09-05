//
//  AnyInsettableShape.swift
//  Ice
//

import SwiftUI

/// A type-erased insettable shape.
struct AnyInsettableShape: InsettableShape {
    private let base: any InsettableShape

    /// Creates a type-erased insettable shape.
    init<S: InsettableShape>(_ shape: S) {
        self.base = shape
    }

    func path(in rect: CGRect) -> Path {
        base.path(in: rect)
    }

    func inset(by amount: CGFloat) -> AnyInsettableShape {
        AnyInsettableShape(base.inset(by: amount))
    }
}
