//
//  Logger+initCategory.swift
//  Ice
//

import Foundation
import OSLog

private let subsystem = Bundle.main.bundleIdentifier!

extension Logger {
    /// Creates a logger using the default subsystem and the
    /// specified category.
    ///
    /// - Parameter category: The string that the system uses
    ///   to categorize emitted signposts.
    init(category: String) {
        self.init(subsystem: subsystem, category: category)
    }
}
