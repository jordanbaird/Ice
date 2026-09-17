//
//  MacOS27SavedItemImages.swift
//  Ice
//

import CoreGraphics
import Foundation
import ImageIO
import OSLog
import UniformTypeIdentifiers

/// Saves captured menu bar item images to disk on macOS 27.
///
/// Items concealed for the Ice Bar aren't drawn, and items in macOS's own
/// overflow are only drawn now and then, so a new capture can be impossible
/// for a long time. Saved images let the Ice Bar keep showing the last real
/// glyph of an item, including after Ice relaunches.
@available(macOS 27.0, *)
@MainActor
enum MacOS27SavedItemImages {
    private static let logger = Logger(category: "MacOS27SavedItemImages")

    /// Images read from or written to disk during this launch.
    private static var loaded = [String: MenuBarItemImageCache.CapturedImage]()

    /// Keys with no saved image, so rendering doesn't hit the disk repeatedly.
    private static var missing = Set<String>()

    private static var directory: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appending(path: "com.jordanbaird.Ice/IceBarImages", directoryHint: .isDirectory)
    }

    /// Apps whose menu bar item keeps changing, such as one that counts down
    /// to the next meeting. A saved picture of those is wrong within minutes,
    /// so they always show their app icon. Set the `IceBarNoPhotoApps` default
    /// to a list of bundle identifiers to change this.
    static var appsWithoutPhotos: Set<String> {
        let stored = UserDefaults.standard.stringArray(forKey: "IceBarNoPhotoApps")
        return Set(stored ?? [])
    }

    /// Whether an item's picture may be taken and saved.
    static func allowsPhoto(_ item: MenuBarItem) -> Bool {
        guard case .string(let bundleIdentifier) = item.tag.namespace else {
            return true
        }
        return !appsWithoutPhotos.contains(bundleIdentifier)
    }

    /// Returns a key for an item that stays the same across launches.
    ///
    /// Items without an accessibility identifier get a new runtime identity
    /// on every launch. They're keyed by their app and their position among
    /// that app's unidentified items, in the order the app lists them.
    static func key(for item: MenuBarItem, among items: [MenuBarItem]) -> String {
        let namespace = String(describing: item.tag.namespace)
        let prefix = MacOS27RuntimeItemIdentity.prefix
        guard item.tag.title.hasPrefix(prefix) else {
            return "\(namespace):\(item.tag.title)#\(item.tag.instanceIndex)"
        }
        let siblings = items
            .filter { $0.tag.namespace == item.tag.namespace && $0.tag.title.hasPrefix(prefix) }
            .sorted { runtimeOrdinal(of: $0) < runtimeOrdinal(of: $1) }
        let position = siblings.firstIndex(matching: item.tag) ?? 0
        return "\(namespace):unidentified#\(position)"
    }

    /// Returns the saved image for a key, if there is one.
    static func image(forKey key: String) -> MenuBarItemImageCache.CapturedImage? {
        if let image = loaded[key] {
            return image
        }
        guard !missing.contains(key), let url = url(forKey: key) else {
            return nil
        }
        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            missing.insert(key)
            return nil
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let dpi = properties?[kCGImagePropertyDPIWidth] as? CGFloat ?? 144
        let image = MenuBarItemImageCache.CapturedImage(cgImage: cgImage, scale: max(1, dpi / 72))
        loaded[key] = image
        return image
    }

    /// Saves an image for a key, replacing any earlier image.
    static func save(_ image: MenuBarItemImageCache.CapturedImage, forKey key: String) {
        if let current = loaded[key], MenuBarItemImageCache.CapturedImage.isVisuallyEqual(current, image) {
            return
        }
        loaded[key] = image
        missing.remove(key)
        guard let directory, let url = url(forKey: key) else {
            return
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            logger.error("Couldn't create \(directory.path, privacy: .public): \(error, privacy: .public)")
            return
        }
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            return
        }
        let dpi = 72 * image.scale
        let properties = [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi] as CFDictionary
        CGImageDestinationAddImage(destination, image.cgImage, properties)
        if !CGImageDestinationFinalize(destination) {
            logger.error("Couldn't save the image for \(key, privacy: .public)")
        }
    }

    private static func url(forKey key: String) -> URL? {
        let name = key.map { character in
            character.isLetter || character.isNumber || character == "-" || character == "." ? character : "_"
        }
        return directory?.appending(path: String(name.prefix(150)) + ".png")
    }

    /// The trailing number of a runtime identity, which follows the order
    /// the owning app lists its items in.
    private static func runtimeOrdinal(of item: MenuBarItem) -> Int {
        item.tag.title.split(separator: ".").last.flatMap { Int($0) } ?? 0
    }
}
