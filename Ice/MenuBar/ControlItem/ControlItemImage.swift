//
//  ControlItemImage.swift
//  Ice
//

import Foundation

/// A Codable image for a control item.
enum ControlItemImage: Codable, Hashable {
    /// An image created from drawing code built into the app.
    case builtin(_ name: ImageBuiltinName)
    /// A system symbol image.
    case symbol(_ name: String)
    /// An image in an asset catalog.
    case catalog(_ name: String)
    /// An image stored as data.
    case data(_ data: Data)
}

extension ControlItemImage {
    /// A name for an image that is created from drawing code in the app.
    enum ImageBuiltinName: Codable, Hashable {
        /// A large chevron.
        case chevronLarge
        /// A small chevron.
        case chevronSmall
    }
}
