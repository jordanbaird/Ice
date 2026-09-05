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
    let isEmpty: Bool

    private var backgroundShape: some InsettableShape {
        if #available(macOS 26.0, *) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
        } else {
            RoundedRectangle(cornerRadius: 9, style: .circular)
        }
    }

    var body: some View {
        barContent
            .containerShape(backgroundShape)
            .clipShape(backgroundShape)
            .contentShape([.interaction, .focusEffect], backgroundShape)
            .overlay {
                backgroundShape
                    .strokeBorder(.quaternary)
            }
    }

    @ViewBuilder
    private var barContent: some View {
        if #available(macOS 27.0, *) {
            mainContent
                .frame(height: 88)
                .frame(maxWidth: .infinity)
                .background(.primary.opacity(0.025))
                .overlay(alignment: .leading) {
                    if isEmpty {
                        Label("Drop an item here", systemImage: "plus")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 20)
                            .allowsHitTesting(false)
                    }
                }
        } else {
            mainContent.frame(height: 48).frame(maxWidth: .infinity)
                .menuBarItemContainer(appState: appState)
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        if #available(macOS 27.0, *) {
            Representable(appState: appState, section: section)
        } else if imageCache.cacheFailed(for: section) {
            Text("Unable to display menu bar items")
                .font(.body)
        } else {
            Representable(appState: appState, section: section)
        }
    }
}
