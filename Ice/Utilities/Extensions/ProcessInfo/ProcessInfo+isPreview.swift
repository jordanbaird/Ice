//
//  ProcessInfo+isPreview.swift
//  Ice
//

import Foundation

extension ProcessInfo {
    /// A Boolean value that indicates whether the process is being
    /// run as a SwiftUI preview.
    var isPreview: Bool {
        #if DEBUG
        environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
        #else
        false
        #endif
    }
}
