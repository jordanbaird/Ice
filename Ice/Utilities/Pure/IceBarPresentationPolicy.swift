//
//  IceBarPresentationPolicy.swift
//  Ice
//

/// Decides whether the Trincano Bar must wait for a cache refresh before it
/// appears.
enum IceBarPresentationPolicy {
    /// The bar waits only when the section has items but there is no image to
    /// show for any of them (nothing useful to draw yet). Otherwise it
    /// appears at once with the cached images and the refresh runs in the
    /// background; the view updates when it finishes.
    static func shouldWaitForRefresh(itemCount: Int, itemsWithImages: Int) -> Bool {
        itemCount > 0 && itemsWithImages == 0
    }
}
