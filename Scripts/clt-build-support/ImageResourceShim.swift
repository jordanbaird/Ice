//
//  ImageResourceShim.swift
//  Ice (CLT build support)
//
//  Replicates the small subset of the asset catalog symbol API that
//  Xcode's actool normally generates. This file is only compiled into
//  the SwiftPM staging build (Scripts/build-without-xcode.sh); the
//  Xcode build generates the real symbols from Assets.xcassets.
//

import SwiftUI
import AppKit

struct ImageResource: Hashable {
    let name: String
    let bundle: Bundle
}

extension ImageResource {
    static let iceCubeStroke = ImageResource(name: "IceCubeStroke", bundle: .main)
}

extension Image {
    init(_ resource: ImageResource) {
        self.init(resource.name, bundle: resource.bundle)
    }
}

extension NSImage {
    /// Backed by the "Warning" imageset in the asset catalog.
    static var warning: NSImage {
        NSImage(named: NSImage.Name("Warning")) ?? NSImage()
    }
}

extension Color {
    /// Backed by the "DefaultLayoutBarColor" colorset in the asset catalog
    /// (actool drops the "Color" suffix when generating the symbol name).
    static let defaultLayoutBar = Color(nsColor: NSColor(name: nil) { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            NSColor(calibratedWhite: 1, alpha: 0.07)
        } else {
            NSColor(calibratedWhite: 0, alpha: 0.17)
        }
    })
}
