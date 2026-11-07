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
        if #available(macOS 26.0, *) {
            contentForm(cornerStyle: .continuous)
        } else {
            contentForm(cornerStyle: .circular)
        }
    }

    @ViewBuilder
    private func contentForm(cornerStyle: RoundedCornerStyle) -> some View {
        IceForm(spacing: 0) {
            mainContent(containerShape: RoundedRectangle(cornerRadius: 20, style: cornerStyle))
            Spacer(minLength: 10)
            bottomBar(containerShape: Capsule(style: cornerStyle))
        }
    }

    @ViewBuilder
    private func mainContent(containerShape: some InsettableShape) -> some View {
        IceSection(spacing: 0, options: .plain) {
            appIconAndCopyrightSection
                .layoutPriority(1)

            Spacer(minLength: 0)
                .frame(maxHeight: 20)

            creditsSection
                .layoutPriority(1)
        }
        .padding(.top, 5)
        .padding([.horizontal, .bottom], 30)
        .frame(maxHeight: 500)
        .background(.quinary, in: containerShape)
        .containerShape(containerShape)
    }

    @ViewBuilder
    private var appIconAndCopyrightSection: some View {
        IceSection(options: .plain) {
            HStack(spacing: 10) {
                if let nsImage = NSImage(named: NSImage.applicationIconName) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 230)
                }

                VStack(alignment: .leading) {
                    Text("Trincano")
                        .font(.system(size: 80))
                        .foregroundStyle(.primary)

                    Text("Version \(Constants.versionString)")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)

                    Text(Constants.copyrightString)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary.opacity(0.67))
                }
                .fontWeight(.medium)
            }
        }
    }

    @ViewBuilder
    private var creditsSection: some View {
        IceSection(options: .plain) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Trincano is a modified version of Ice by Jordan Baird, released under the GNU General Public License v3.0. Modified by Paulo Victor T Silva (PILUTECH), 2026.")
                Text("Everything stays on your Mac: Trincano has no telemetry and does not check for updates.")
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
            .frame(maxWidth: 600, alignment: .leading)
        }
    }

    @ViewBuilder
    private func bottomBar(containerShape: some InsettableShape) -> some View {
        HStack {
            Button("Quit Trincano") {
                NSApp.terminate(nil)
            }
            Spacer()
            Button("Acknowledgements") {
                NSWorkspace.shared.open(acknowledgementsURL)
            }
            Button("Original Ice") {
                openURL(upstreamURL)
            }
            Button("License") {
                openURL(licenseURL)
            }
            Button("Source Code") {
                openURL(contributeURL)
            }
            Button("Report a Bug") {
                openURL(issuesURL)
            }
        }
        .padding(8)
        .buttonStyle(BottomBarButtonStyle())
        .background(.quinary, in: containerShape)
        .containerShape(containerShape)
        .frame(height: 40)
    }
}

private struct BottomBarButtonStyle: ButtonStyle {
    @State private var isHovering = false

    private var borderShape: some InsettableShape {
        ContainerRelativeShape()
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background {
                borderShape
                    .fill(configuration.isPressed ? .tertiary : .quaternary)
                    .opacity(isHovering ? 1 : 0)
            }
            .contentShape([.focusEffect, .interaction], borderShape)
            .onHover { hovering in
                isHovering = hovering
            }
    }
}
