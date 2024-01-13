//
//  BoxObject.swift
//  Ice
//

/// An object that contains a base value.
class BoxObject<Base> {
    /// The value at the base of this box.
    var base: Base

    /// Creates a box with the given base value.
    init(base: Base) {
        self.base = base
    }
}

extension BoxObject where Base: ExpressibleByNilLiteral {
    /// Creates a box with a `nil` base value.
    convenience init() {
        self.init(base: nil)
    }
}
