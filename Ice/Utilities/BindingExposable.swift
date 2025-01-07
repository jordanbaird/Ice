//
//  BindingExposable.swift
//  Ice
//

import SwiftUI

/// A type that exposes its writable properties as bindings.
protocol BindingExposable {
    /// A lens that exposes bindings to the writable properties of this type.
    typealias Bindings = ExposedBindings<Self>

    /// A lens that exposes bindings to the writable properties of this instance.
    var bindings: Bindings { get }
}

extension BindingExposable {
    var bindings: Bindings {
        Bindings(base: self)
    }
}

/// A lens that exposes bindings to the writable properties of a base object.
@dynamicMemberLookup
struct ExposedBindings<Base: BindingExposable> {
    /// The object whose bindings are exposed.
    private let base: Base

    /// Creates a lens that exposes the bindings of the given object.
    init(base: Base) {
        self.base = base
    }

    /// Returns a binding to the property at the given key path.
    subscript<Value>(dynamicMember keyPath: ReferenceWritableKeyPath<Base, Value>) -> Binding<Value> {
        Binding(get: { base[keyPath: keyPath] }, set: { base[keyPath: keyPath] = $0 })
    }

    /// Returns a lens that exposes the bindings of the object at the given key path.
    subscript<T: BindingExposable>(dynamicMember keyPath: KeyPath<Base, T>) -> ExposedBindings<T> {
        ExposedBindings<T>(base: base[keyPath: keyPath])
    }
}
