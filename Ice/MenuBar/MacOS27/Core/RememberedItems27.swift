//
//  RememberedItems27.swift
//  Ice
//

import CoreGraphics
import Foundation

/// One menu bar item as Ice remembers it between runs.
///
/// A concealed application publishes nothing through Accessibility on macOS 27, so what Ice
/// knows of its items is only what it saw while they were on the bar. Reading the bar once
/// before the first concealment is a race Ice loses whenever that read lands before the
/// applications have published, and the Ice Bar then stays empty for the whole session
/// (measured 2026-11-04). What was written down last time settles it.
struct RememberedItem27: Equatable {
    var tag: String
    var windowID: UInt32
    var bounds: CGRect
    var title: String?
}

/// Turns remembered items into what goes in the preferences, and back.
///
/// The shape is fixed by what is already on people's disks under `MacOS27RememberedItems`:
/// a dictionary of bundle identifier to an array of records, each with `tag`, `windowID` as
/// a number, `x`, `y`, `width`, `height`, and `title` when there is one.
enum RememberedItems27 {
    private enum Key {
        static let tag = "tag"
        static let windowID = "windowID"
        static let x = "x"
        static let y = "y"
        static let width = "width"
        static let height = "height"
        static let title = "title"
    }

    static func encode(_ items: [String: [RememberedItem27]]) -> [String: [[String: Any]]] {
        items.mapValues { records in
            records.map { record in
                var stored: [String: Any] = [
                    Key.tag: record.tag,
                    Key.windowID: NSNumber(value: record.windowID),
                    Key.x: record.bounds.minX,
                    Key.y: record.bounds.minY,
                    Key.width: record.bounds.width,
                    Key.height: record.bounds.height,
                ]
                if let title = record.title {
                    stored[Key.title] = title
                }
                return stored
            }
        }
    }

    /// The same, from the untyped dictionary the preferences hand back.
    ///
    /// Casting the whole thing to `[String: [[String: Any]]]` in one go checks every value, so
    /// a single application's entry in the wrong shape — an older or newer Ice, a hand-edited
    /// plist, a file caught half-written — threw the entire remembered set away. That is the
    /// failure the store exists to prevent: with nothing remembered, every concealed
    /// application's items are unknown and the Ice Bar is empty for the whole session. One bad
    /// entry now costs that one application.
    static func decode(anyStored: [String: Any]) -> [String: [RememberedItem27]] {
        decode(anyStored.compactMapValues { $0 as? [[String: Any]] })
    }

    /// A record Ice cannot read is dropped on its own; the rest of that application's items,
    /// and every other application, come back as they were. An application left with nothing
    /// is left out, so a caller never has to tell "remembered, and it had no items" from
    /// "not remembered".
    static func decode(_ stored: [String: [[String: Any]]]) -> [String: [RememberedItem27]] {
        var decoded = [String: [RememberedItem27]]()
        for (bundleID, records) in stored {
            let items = records.compactMap { record -> RememberedItem27? in
                // Every number goes through `NSNumber`. A value read back from the
                // preferences is one, but a value put here by anything else may be a plain
                // `Double`, and `Any` holding a `Double` does not cast to `CGFloat`.
                guard
                    let tag = record[Key.tag] as? String,
                    let windowID = (record[Key.windowID] as? NSNumber)?.uint32Value,
                    let x = (record[Key.x] as? NSNumber)?.doubleValue,
                    let y = (record[Key.y] as? NSNumber)?.doubleValue,
                    let width = (record[Key.width] as? NSNumber)?.doubleValue,
                    let height = (record[Key.height] as? NSNumber)?.doubleValue
                else {
                    return nil
                }
                return RememberedItem27(
                    tag: tag,
                    windowID: windowID,
                    bounds: CGRect(x: x, y: y, width: width, height: height),
                    title: record[Key.title] as? String
                )
            }
            if !items.isEmpty {
                decoded[bundleID] = items
            }
        }
        return decoded
    }

    /// What identifies the remembered set, for deciding whether it is worth writing again.
    ///
    /// Where an item is drawn is left out on purpose: the bar moves its items constantly, and
    /// writing on every read would be writing all day for nothing.
    static func signature(of items: [String: [RememberedItem27]]) -> String {
        items
            .flatMap { bundleID, records in records.map { "\(bundleID)|\($0.tag)|\($0.windowID)" } }
            .sorted()
            .joined(separator: "\n")
    }
}
