//
//  IconAssetsTests.swift
//  TrincanoTests
//

import Foundation
import ImageIO
import Testing

/// Checks the app icon and the menu bar glyph assets (Frost Bar identity).
struct IconAssetsTests {
    private var catalog: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Ice/Resources/Assets.xcassets")
    }

    private func pixelSize(of url: URL) -> (width: Int, height: Int, hasAlpha: Bool)? {
        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = props[kCGImagePropertyPixelWidth] as? Int,
            let height = props[kCGImagePropertyPixelHeight] as? Int
        else {
            return nil
        }
        return (width, height, (props[kCGImagePropertyHasAlpha] as? Bool) ?? false)
    }

    @Test func appIconHasEverySizeWithTheRightPixels() throws {
        let expected: [(String, Int)] = [
            ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
            ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
            ("icon_512x512", 512), ("icon_512x512@2x", 1024),
        ]
        for (name, side) in expected {
            let url = catalog.appendingPathComponent("AppIcon.appiconset/\(name).png")
            let size = try #require(pixelSize(of: url), "\(name) missing or unreadable")
            #expect(size.width == side && size.height == side, "\(name): \(size)")
            #expect(size.hasAlpha, "\(name) needs transparent margins")
        }
    }

    @Test func menuBarGlyphsAre18PointTemplatesAtEveryScale() throws {
        for name in ["FrostBarFill", "FrostBarStroke"] {
            let dir = catalog.appendingPathComponent("ControlItemImages/FrostBar/\(name).imageset")
            for (suffix, side) in [("", 18), ("@2x", 36), ("@3x", 54)] {
                let url = dir.appendingPathComponent("\(name)\(suffix).png")
                let size = try #require(pixelSize(of: url), "\(name)\(suffix) missing")
                #expect(size.width == side && size.height == side, "\(name)\(suffix): \(size)")
                #expect(size.hasAlpha)
            }
            let json = try Data(contentsOf: dir.appendingPathComponent("Contents.json"))
            let object = try #require(try JSONSerialization.jsonObject(with: json) as? [String: Any])
            let properties = object["properties"] as? [String: Any]
            #expect(properties?["template-rendering-intent"] as? String == "template", "\(name) must be a template")
        }
    }
}
