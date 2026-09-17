//
//  MacOS27GlyphDebug.swift
//  Ice
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Writes macOS 27 menu bar glyph captures to disk for troubleshooting.
///
/// Disabled unless the `DebugDumpMacOS27Glyphs` user default is set. Files
/// are written to `~/Library/Caches/com.jordanbaird.Ice/GlyphDebug`.
enum MacOS27GlyphDebug {
    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: "DebugDumpMacOS27Glyphs")
    }

    private static var directory: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appending(path: "com.jordanbaird.Ice/GlyphDebug", directoryHint: .isDirectory)
    }

    /// Writes an image as a PNG file with the given name.
    static func write(_ image: CGImage, name: String) {
        guard isEnabled, let directory else {
            return
        }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: fileName(for: name) + ".png")
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            return
        }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }

    /// Appends a line to the debug log file.
    static func log(_ line: String) {
        guard isEnabled, let directory else {
            return
        }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "glyphs.txt")
        let data = Data((line + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }

    private static func fileName(for name: String) -> String {
        let characters = name.map { character in
            character.isLetter || character.isNumber || character == "-" || character == "." ? character : "_"
        }
        return String(characters.prefix(120))
    }
}
