//
//  MenuBarSpacingPreview.swift
//  Ice
//

import Cocoa
import SwiftUI

/// Live demo of menu bar item spacing, rendered with the user's real icons.
///
/// The strip re-lays out instantly as the slider moves, so the user can see
/// what a spacing value looks like before applying it (applying still needs
/// a logout on macOS 26+). Icons are app icons, not item screenshots, because
/// item windows already contain the current system spacing baked in.
struct MenuBarSpacingPreview: View {
    /// An icon to show in the preview strip.
    enum PreviewIcon: Hashable {
        case image(NSImage)
        case system(String)

        func hash(into hasher: inout Hasher) {
            switch self {
            case .image(let image):
                hasher.combine(ObjectIdentifier(image))
            case .system(let name):
                hasher.combine(name)
            }
        }

        static func == (lhs: PreviewIcon, rhs: PreviewIcon) -> Bool {
            switch (lhs, rhs) {
            case (.image(let a), .image(let b)):
                a === b
            case (.system(let a), .system(let b)):
                a == b
            default:
                false
            }
        }
    }

    /// Fallback symbols when real icons are unavailable (e.g. missing permissions).
    static let fallbackIcons: [PreviewIcon] = [
        .system("wifi"),
        .system("battery.75"),
        .system("magnifyingglass"),
        .system("bell.fill"),
        .system("clock"),
        .system("record.circle"),
    ]

    /// Icons to lay out, left to right.
    var icons: [PreviewIcon]

    /// Absolute gap between icons in points (system default is 16).
    var spacing: CGFloat

    /// Menu bar background color, when known.
    var barColor: Color?

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: spacing) {
                ForEach(Array(icons.enumerated()), id: \.offset) { _, icon in
                    switch icon {
                    case .image(let nsImage):
                        Image(nsImage: nsImage)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 18)
                    case .system(let name):
                        Image(systemName: name)
                            .font(.system(size: 14))
                            .frame(height: 18)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .background {
                if let barColor {
                    barColor
                } else {
                    // ponytail: real wallpaper blur needs a desktop capture;
                    // neutral fill communicates spacing just as well.
                    Color(nsColor: .windowBackgroundColor)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(.quaternary, lineWidth: 1)
            }

            HStack {
                Text("Gap: \(Int(spacing)) pt")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                Text("Live demo — real icons may carry their own padding")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
