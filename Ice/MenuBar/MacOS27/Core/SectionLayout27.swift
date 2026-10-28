//
//  SectionLayout27.swift
//  Ice
//

import CoreGraphics
import Foundation

/// A section as the macOS 27 backend sees it, ordered from most to least visible.
enum MacOS27Section: Int, Codable, CaseIterable, Comparable {
    case visible = 0
    case hidden = 1
    case alwaysHidden = 2

    static func < (lhs: MacOS27Section, rhs: MacOS27Section) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Which section each application belongs to.
///
/// macOS 27 hides whole applications, not single items, so the layout is kept
/// per bundle identifier.
enum SectionLayout27 {
    /// Collapses per-item sections into one section per application.
    ///
    /// An application whose items sit in different sections takes its most
    /// visible section, so an item the user left visible is never hidden.
    static func appSections(items: [(bundleID: String, section: MacOS27Section)]) -> [String: MacOS27Section] {
        items.reduce(into: [:]) { result, item in
            result[item.bundleID] = min(result[item.bundleID] ?? item.section, item.section)
        }
    }

    /// The layout to act on for the running applications.
    ///
    /// What was observed now wins, the saved layout covers applications whose
    /// items could not be read, and an application seen for the first time is
    /// visible.
    static func effectiveLayout(
        observed: [String: MacOS27Section],
        saved: [String: MacOS27Section],
        running: Set<String>
    ) -> [String: MacOS27Section] {
        running.reduce(into: [:]) { result, bundleID in
            result[bundleID] = observed[bundleID] ?? saved[bundleID] ?? .visible
        }
    }

    /// The sections the bar itself held before macOS 27, read once from the order of its items.
    ///
    /// Until macOS 27 an item's section *was* its place on the bar, between Ice's dividers, and
    /// nothing wrote it down — the bar was the record. On 27 the record has to be a saved layout,
    /// and an application missing from it is visible, so an upgrade used to leave Ice hiding
    /// nothing at all until the whole layout was rebuilt by hand (reported on jordanbaird/Ice#1006).
    /// The order still stands at the first launch after the upgrade, so it is read there.
    ///
    /// Returns `nil` when the bar cannot be read that way: with nothing to the right of the hidden
    /// divider there is no visible section, which is what a bar macOS 27 has already rearranged
    /// looks like — its dividers drift to the end, and every item would read as hidden.
    ///
    /// - Parameters:
    ///   - items: The manageable items on the bar, each with the bundle identifier of the
    ///     application that created it. Ice's own dividers are not among them.
    ///   - hiddenControlItem: The bounds of the divider for the hidden section.
    ///   - alwaysHiddenControlItem: The bounds of the divider for the always-hidden section,
    ///     if that section is enabled.
    static func seededLayout(
        items: [(bundleID: String, bounds: CGRect)],
        hiddenControlItem: CGRect,
        alwaysHiddenControlItem: CGRect?
    ) -> [String: MacOS27Section]? {
        let sections = items.compactMap { item -> (bundleID: String, section: MacOS27Section)? in
            section(of: item.bounds, hiddenControlItem: hiddenControlItem, alwaysHiddenControlItem: alwaysHiddenControlItem)
                .map { (item.bundleID, $0) }
        }
        guard sections.contains(where: { $0.section == .visible }) else {
            return nil
        }
        return appSections(items: sections)
    }

    /// The section an item's bounds put it in, or `nil` for one lying across a divider.
    ///
    /// The rules are the ones Ice used on the bar before macOS 27.
    private static func section(
        of bounds: CGRect,
        hiddenControlItem: CGRect,
        alwaysHiddenControlItem: CGRect?
    ) -> MacOS27Section? {
        if bounds.minX >= hiddenControlItem.maxX {
            return .visible
        }
        guard bounds.maxX <= hiddenControlItem.minX else {
            return nil
        }
        guard let alwaysHiddenControlItem else {
            return .hidden
        }
        if bounds.minX >= alwaysHiddenControlItem.maxX {
            return .hidden
        }
        return bounds.maxX <= alwaysHiddenControlItem.minX ? .alwaysHidden : nil
    }

    /// The applications whose section is one of the given sections.
    static func bundles(in sections: Set<MacOS27Section>, layout: [String: MacOS27Section]) -> Set<String> {
        Set(layout.compactMap { sections.contains($0.value) ? $0.key : nil })
    }
}
