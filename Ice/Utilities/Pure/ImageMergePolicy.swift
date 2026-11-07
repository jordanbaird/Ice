//
//  ImageMergePolicy.swift
//  Ice
//

/// Decides how newly captured menu bar item images replace cached ones.
///
/// An app-icon fallback stands in for a window that could not be captured.
/// It must never replace an image that was really captured, but a real
/// capture always replaces a fallback.
///
/// Images whose key is no longer valid (the item left the menu bar) are
/// evicted so the cache doesn't grow for the whole lifetime of the app.
/// Idea from lxy1992/Ice (`Evict stale menu bar item images`).
enum ImageMergePolicy {
    static func merge<Key: Hashable, Image>(
        old: [Key: Image],
        new: [Key: Image],
        isFallback: (Image) -> Bool,
        keepingOnly validKeys: Set<Key>? = nil
    ) -> [Key: Image] {
        let merged = old.merging(new) { old, new in
            if isFallback(new), !isFallback(old) {
                old
            } else {
                new
            }
        }
        // Filter the final result: a late capture of an item that already left
        // must not come back (even when `validKeys` is empty).
        guard let validKeys else {
            return merged
        }
        return merged.filter { validKeys.contains($0.key) }
    }
}
