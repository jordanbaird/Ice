//
//  ImageMergePolicy.swift
//  Ice
//

/// Decides how newly captured menu bar item images replace cached ones.
///
/// An app-icon fallback stands in for a window that could not be captured.
/// It must never replace an image that was really captured, but a real
/// capture always replaces a fallback.
enum ImageMergePolicy {
    static func merge<Key: Hashable, Image>(
        old: [Key: Image],
        new: [Key: Image],
        isFallback: (Image) -> Bool
    ) -> [Key: Image] {
        old.merging(new) { old, new in
            if isFallback(new), !isFallback(old) {
                old
            } else {
                new
            }
        }
    }
}
