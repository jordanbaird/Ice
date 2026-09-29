//
//  SectionLayout27.swift
//  Ice
//

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

    /// The applications whose section is one of the given sections.
    static func bundles(in sections: Set<MacOS27Section>, layout: [String: MacOS27Section]) -> Set<String> {
        Set(layout.compactMap { sections.contains($0.value) ? $0.key : nil })
    }
}
