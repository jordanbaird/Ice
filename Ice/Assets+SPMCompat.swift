//
//  Assets+SPMCompat.swift
//  Ice
//

import SwiftUI

// The upstream project relies on asset catalog accessors that Xcode 15+
// auto-generates (ImageResource and Color extensions). SwiftPM toolchains
// older than Swift 6 do not generate these accessors, so define them
// manually here. The entire file is guarded by SWIFT_PACKAGE, so the
// canonical Xcode build (which auto-generates the same accessors) is
// unaffected and does not conflict with these declarations.

#if SWIFT_PACKAGE

extension ImageResource {
    /// The "IceCubeStroke" image in the asset catalog.
    static let iceCubeStroke = ImageResource(name: "IceCubeStroke", bundle: .module)
}

extension NSImage {
    /// The "Warning" image in the asset catalog.
    static let warning: NSImage = {
        guard let image = NSImage(named: "Warning") else {
            fatalError("Missing asset catalog image: Warning")
        }
        return image
    }()
}

extension Color {
    /// The "DefaultLayoutBarColor" color in the asset catalog.
    static let defaultLayoutBar = Color("DefaultLayoutBarColor", bundle: .module)
}

#endif
