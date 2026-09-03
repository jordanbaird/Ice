//
//  HelpSettingsPane.swift
//  Ice
//

import SwiftUI

struct HelpSettingsPane: View {
    @Environment(\.openURL) private var openURL

    private var frequentIssuesURL: URL {
        URL(string: "https://github.com/jordanbaird/Ice/blob/main/FREQUENT_ISSUES.md")!
    }

    private var issuesURL: URL {
        URL(string: "https://github.com/jordanbaird/Ice/issues")!
    }

    private var websiteURL: URL {
        URL(string: "https://icemenubar.app")!
    }

    var body: some View {
        IceForm {
            gettingStartedSection
            frequentIssuesSection
            moreHelpSection
        }
    }

    @ViewBuilder
    private var gettingStartedSection: some View {
        IceSection("Getting Started") {
            HelpItem(
                symbol: "cursorarrow.click",
                title: "Show or hide the hidden section",
                text: "Click the Ice icon in the menu bar to show or hide the items in the hidden section."
            )
            HelpItem(
                symbol: "option",
                title: "Show or hide the always-hidden section",
                text: "Hold Option and click the Ice icon to show or hide the items in the always-hidden section."
            )
            HelpItem(
                symbol: "arrow.left.arrow.right",
                title: "Arrange menu bar items",
                text: "Hold Command and drag an item in the menu bar to move it to a different section, or drag items in the Menu Bar Layout settings."
            )
            HelpItem(
                symbol: "keyboard",
                title: "Use hotkeys",
                text: "Assign keyboard shortcuts in the Hotkeys settings to toggle sections, search menu bar items, and more."
            )
        }
    }

    @ViewBuilder
    private var frequentIssuesSection: some View {
        IceSection("Frequent Issues") {
            HelpIssue(
                title: "Items are moved to the always-hidden section",
                text: "macOS adds new items to the far left of the menu bar, which is where the always-hidden section lives. Apps that do not remember the position of their items are treated as new each time they appear, so their items end up in the always-hidden section. Ice cannot yet move individual items back automatically."
            )
            HelpIssue(
                title: "Ice removed an item",
                text: "Ice cannot remove items. The item was most likely placed in the always-hidden section by macOS. Hold Option and click the Ice icon to show the always-hidden section, then hold Command and drag the item into a different section."
            )
            HelpIssue(
                title: "Ice does not remember the order of items",
                text: "This is a missing feature rather than a bug. Ice manages sections, not the position of individual items within them."
            )
            HelpIssue(
                title: "“Ice cannot arrange menu bar items in automatically hidden menu bars”",
                text: "Open System Settings, go to Control Center, and set “Automatically hide and show the menu bar” to Never. Arrange your menu bar items in Ice, then restore your preferred setting."
            )
        }
    }

    @ViewBuilder
    private var moreHelpSection: some View {
        IceSection("More Help") {
            HStack {
                Button("Frequent Issues") {
                    openURL(frequentIssuesURL)
                }
                Button("Report a Bug") {
                    openURL(issuesURL)
                }
                Button("Ice Website") {
                    openURL(websiteURL)
                }
                Spacer()
            }
        }
    }
}

/// A row in the "Getting Started" section.
private struct HelpItem: View {
    let symbol: String
    let title: LocalizedStringKey
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(text)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}

/// An expandable row in the "Frequent Issues" section.
private struct HelpIssue: View {
    let title: LocalizedStringKey
    let text: LocalizedStringKey

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    Text(title)
                        .font(.headline)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isButton)

            if isExpanded {
                Text(text)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)
                    .padding(.leading, 20)
            }
        }
        .padding(.vertical, 4)
    }
}
