//
//  MenuBarSearchSummary.swift
//  Ice
//

/// What the footer and the list of the menu bar search show for the current
/// query: the total, a filtered count, or the "no results" state.
enum MenuBarSearchSummary: Equatable {
    /// No query: every item of the menu bar is listed.
    case total(Int)
    /// A query that matched some of the items.
    case filtered(shown: Int, total: Int)
    /// A query that matched nothing. The query is trimmed for display.
    case noResults(query: String)

    init(query: String, shown: Int, total: Int) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            self = .total(total)
        } else if shown <= 0 {
            self = .noResults(query: trimmed)
        } else {
            self = .filtered(shown: shown, total: max(total, shown))
        }
    }

    var isNoResults: Bool {
        if case .noResults = self { true } else { false }
    }
}
