//
//  BindingExposable.swift
//  Ice
//

import SwiftUI

/// A type that acts as a lens that exposes bindings to the
/// writable properties on a base object.
@dynamicMemberLookup
struct ExposedBindings<Base> {
    /// The base object whose bindings are exposed.
    let base: Base

    /// Returns a binding to the writable property at the given
    /// key path.
    subscript<Value>(
        dynamicMember keyPath: ReferenceWritableKeyPath<Base, Value>
    ) -> Binding<Value> {
        Binding(
            get: {
                base[keyPath: keyPath]
            },
            set: { newValue in
                base[keyPath: keyPath] = newValue
            }
        )
    }
}

/// A type that exposes its writable properties as bindings.
protocol BindingExposable {
    /// A type that acts as a lens that exposes bindings to the
    /// writable properties on this type.
    typealias Bindings = ExposedBindings<Self>

    /// A lens that exposes bindings to the writable properties
    /// on this instance.
    var bindings: Bindings { get }
}

extension BindingExposable {
    var bindings: Bindings {
        Bindings(base: self)
    }
}
