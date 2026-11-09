//
//  LayoutBar.swift
//  Ice
//

import SwiftUI

struct LayoutBar: View {
    private struct Representable: NSViewRepresentable {
        let appState: AppState
        let section: MenuBarSection.Name

        func makeNSView(context: Context) -> LayoutBarScrollView {
            LayoutBarScrollView(appState: appState, section: section)
        }

        func updateNSView(_ nsView: LayoutBarScrollView, context: Context) { }
    }

    @EnvironmentObject var appState: AppState
    @ObservedObject var imageCache: MenuBarItemImageCache

    let section: MenuBarSection.Name

    /// A Boolean value that indicates whether the section has no items, to
    /// show the invitation to drag items into it.
    var isEmpty = false

    private var backgroundShape: some InsettableShape {
        if #available(macOS 26.0, *) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
        } else {
            RoundedRectangle(cornerRadius: 9, style: .circular)
        }
    }

    var body: some View {
        mainContent
            .frame(height: 48)
            .frame(maxWidth: .infinity)
            .menuBarItemContainer(appState: appState)
            .containerShape(backgroundShape)
            .clipShape(backgroundShape)
            .contentShape([.interaction, .focusEffect], backgroundShape)
            .overlay {
                backgroundShape
                    .strokeBorder(.quaternary)
            }
            .overlay {
                if isEmpty {
                    Text("Drag items here")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .allowsHitTesting(false)
                }
            }
    }

    @ViewBuilder
    private var mainContent: some View {
        if imageCache.cacheFailed(for: section) {
            Text("Unable to display menu bar items")
                .font(.body)
        } else {
            Representable(appState: appState, section: section)
        }
    }
}
