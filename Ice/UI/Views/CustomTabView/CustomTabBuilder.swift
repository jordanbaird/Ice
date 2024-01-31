//
//  CustomTabBuilder.swift
//  Ice
//

/// A result builder type that builds an array of tabs
/// for a custom tab view.
@resultBuilder
enum CustomTabBuilder {
    static func buildBlock(_ components: CustomTab...) -> [CustomTab] {
        components
    }
}
