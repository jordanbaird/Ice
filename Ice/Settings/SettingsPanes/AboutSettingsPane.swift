//
//  AboutSettingsPane.swift
//  Ice
//

import SwiftUI

struct AboutSettingsPane: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openURL) private var openURL

    private var acknowledgementsURL: URL {
        // swiftlint:disable:next force_unwrapping
        Bundle.main.url(forResource: "Acknowledgements", withExtension: "pdf")!
    }

    private var contributeURL: URL {
        URL(string: "https://github.com/PiluVitu/trincano")!
    }

    private var upstreamURL: URL {
        URL(string: "https://github.com/jordanbaird/Ice")!
    }

    private var licenseURL: URL {
        contributeURL.appendingPathComponent("blob/main/LICENSE")
    }

    private var issuesURL: URL {
        contributeURL.appendingPathComponent("issues")
    }

    var body: some View {
        IceForm(alignment: .leading, spacing: 14) {
            header

            IceSection("Provenance and license") {
                provenanceRow(
                    title: "Origin",
                    value: Text("Modified version of Ice, by Jordan Baird."),
                    detail: Text("Not affiliated with or endorsed by the Ice project."),
                    action: ("Original Ice", { openURL(upstreamURL) })
                )
                provenanceRow(
                    title: "License",
                    value: Text(verbatim: "GNU General Public License v3.0"),
                    action: ("View License", { openURL(licenseURL) })
                )
                provenanceRow(
                    title: "Modified by",
                    value: Text(verbatim: "Paulo Victor T Silva (PILUTECH), 2026")
                )
                provenanceRow(
                    title: "Source Code",
                    value: Text(verbatim: "github.com/PiluVitu/trincano"),
                    action: ("Open", { openURL(contributeURL) })
                )
                provenanceRow(
                    title: "Other credits",
                    value: Text("Third-party libraries used by the app."),
                    action: ("Open Acknowledgements", { NSWorkspace.shared.open(acknowledgementsURL) }),
                    showsExternalIcon: false
                )
            }

            IceSection("Privacy") {
                provenanceRow(
                    title: nil,
                    value: Text("Everything stays on your Mac: Trincano has no telemetry and does not check for updates.")
                )
            }

            Spacer(minLength: 0)

            footer
        }
    }

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 16) {
            if let nsImage = NSImage(named: NSImage.applicationIconName) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 72)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Trincano")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.primary)

                Text("Version \(Constants.versionString)")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Text(Constants.copyrightString)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    /// A labeled row of the provenance sheet. Long values wrap inside the
    /// row and the action stays aligned to the trailing edge.
    @ViewBuilder
    private func provenanceRow(
        title: LocalizedStringKey?,
        value: Text,
        detail: Text? = nil,
        action: (title: LocalizedStringKey, perform: () -> Void)? = nil,
        showsExternalIcon: Bool = true
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            if let title {
                Text(title)
                    .foregroundStyle(.secondary)
                    .frame(width: 120, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 2) {
                value
                if let detail {
                    detail.font(.callout).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)

            if let action {
                Button {
                    action.perform()
                } label: {
                    HStack(spacing: 4) {
                        Text(action.title)
                        if showsExternalIcon {
                            Image(systemName: "arrow.up.right")
                                .imageScale(.small)
                                .accessibilityHidden(true)
                        }
                    }
                }
                .controlSize(.small)
            }
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: 8) {
            Button("Report a Bug") {
                openURL(issuesURL)
            }
            Spacer(minLength: 0)
            Button("Quit Trincano") {
                NSApp.terminate(nil)
            }
        }
    }
}
