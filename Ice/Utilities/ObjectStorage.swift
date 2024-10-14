//
//  ObjectStorage.swift
//  Ice
//

import ObjectiveC

// MARK: - Object Storage

/// A type that uses the Objective-C runtime to store values of a given
/// type with an object.
final class ObjectStorage<Value> {
    /// The association policy to use for storage.
    ///
    /// - Note: Regardless of whether a value is stored with a strong or
    ///   weak reference, the association is made strongly. Weak references
    ///   are stored inside a `WeakReference` object.
    private let policy = objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC

    /// The key used for value lookup.
    ///
    /// The key is unique to this instance.
    private var key: UnsafeRawPointer {
        UnsafeRawPointer(Unmanaged.passUnretained(self).toOpaque())
    }

    /// Sets the value for the given object.
    ///
    /// If the value is an object, it is stored with a strong reference.
    /// Use ``weakSet(_:for:)`` to store an object with a weak reference.
    ///
    /// - Parameters:
    ///   - value: A value to set.
    ///   - object: An object to set the value for.
    func set(_ value: Value?, for object: AnyObject) {
        objc_setAssociatedObject(object, key, value, policy)
    }

    /// Retrieves the value stored for the given object.
    ///
    /// - Parameter object: An object to retrieve the value for.
    func value(for object: AnyObject) -> Value? {
        let value = objc_getAssociatedObject(object, key)
        return if let container = value as? WeakReference {
            container.object as? Value
        } else {
            value as? Value
        }
    }
}

// MARK: - Weak Storage

/// An object containing a weak reference to another object.
private final class WeakReference {
    /// A weak reference to an object.
    private(set) weak var object: AnyObject?

    /// Creates a weak reference to an object.
    init(_ object: AnyObject) {
        self.object = object
    }
}

extension ObjectStorage where Value: AnyObject {
    /// Sets a weak reference to an object.
    ///
    /// - Parameters:
    ///   - value: An object to set a weak reference to.
    ///   - object: An object to set the weak reference for.
    func weakSet(_ value: Value?, for object: AnyObject) {
        objc_setAssociatedObject(object, key, value.map(WeakReference.init), policy)
    }
}
