//
//  AboutSettingsPane.swift
//  Ice
//

import SwiftUI

struct AboutSettingsPane: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openURL) private var openURL

    private var updatesManager: UpdatesManager {
        appState.updatesManager
    }

    private var generalSettingsManager: GeneralSettingsManager {
        appState.settingsManager.generalSettingsManager
    }

    private var acknowledgementsURL: URL {
        // swiftlint:disable:next force_unwrapping
        Bundle.main.url(forResource: "Acknowledgements", withExtension: "pdf")!
    }

    private var contributeURL: URL {
        // swiftlint:disable:next force_unwrapping
        URL(string: "https://github.com/jordanbaird/Ice")!
    }

    private var issuesURL: URL {
        contributeURL.appendingPathComponent("issues")
    }

    private var donateURL: URL {
        // swiftlint:disable:next force_unwrapping
        URL(string: "https://icemenubar.app/Donate")!
    }

    private var lastUpdateCheckString: String {
        if let date = updatesManager.lastUpdateCheckDate {
            date.formatted(date: .abbreviated, time: .standard)
        } else {
            "Never".localized(for: generalSettingsManager.language)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            mainForm
            Spacer(minLength: 20)
            bottomBar
        }
        .padding(30)
    }

    @ViewBuilder
    private var mainForm: some View {
        IceForm(padding: EdgeInsets(top: 5, leading: 30, bottom: 30, trailing: 30), spacing: 0) {
            appIconAndCopyrightSection
                .layoutPriority(1)

            Spacer(minLength: 0)
                .frame(maxHeight: 20)

            updatesSection
                .layoutPriority(1)
        }
        .scrollDisabled(true)
        .frame(maxHeight: 500)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 20, style: .circular))
    }

    @ViewBuilder
    private var appIconAndCopyrightSection: some View {
        IceSection(options: .plain) {
            HStack(spacing: 10) {
                if let nsImage = NSImage(named: NSImage.applicationIconName) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 225)
                }

                VStack(alignment: .leading) {
                    Text(verbatim: "Ice".localized(for: generalSettingsManager.language))
                        .font(.system(size: 72, weight: .medium))
                        .foregroundStyle(.primary)

                    Text(verbatim: "Version ".localized(for: generalSettingsManager.language) + Constants.versionString)
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)

                    Text(Constants.copyrightString)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    @ViewBuilder
    private var updatesSection: some View {
        IceSection(options: .hasDividers) {
            automaticallyCheckForUpdates
            automaticallyDownloadUpdates
            if updatesManager.canCheckForUpdates {
                checkForUpdates
            }
        }
        .frame(maxWidth: 600)
    }

    @ViewBuilder
    private var automaticallyCheckForUpdates: some View {
        Toggle(isOn: updatesManager.bindings.automaticallyChecksForUpdates) {
            Text(verbatim: "Automatically check for updates".localized(for: generalSettingsManager.language))
        }
    }

    @ViewBuilder
    private var automaticallyDownloadUpdates: some View {
        Toggle(isOn: updatesManager.bindings.automaticallyDownloadsUpdates) {
            Text(verbatim: "Automatically download updates".localized(for: generalSettingsManager.language))
        }
    }

    @ViewBuilder
    private var checkForUpdates: some View {
        HStack {
            Button {
                updatesManager.checkForUpdates()
            } label: {
                Text(verbatim: "Check for Updates".localized(for: generalSettingsManager.language))
            }
            Spacer()
            Text(verbatim: "Last checked: ".localized(for: generalSettingsManager.language) + lastUpdateCheckString)
                .font(.caption)
        }
    }

    @ViewBuilder
    private var bottomBar: some View {
        HStack {
            Button {
                NSApp.terminate(nil)
            } label: {
                Text(verbatim: "Quit Ice".localized(for: generalSettingsManager.language))
            }
            Spacer()
            Button {
                NSWorkspace.shared.open(acknowledgementsURL)
            } label: {
                Text(verbatim: "Acknowledgements".localized(for: generalSettingsManager.language))
            }
            Button {
                openURL(contributeURL)
            } label: {
                Text(verbatim: "Contribute".localized(for: generalSettingsManager.language))
            }
            Button {
                openURL(issuesURL)
            } label: {
                Text(verbatim: "Report a Bug".localized(for: generalSettingsManager.language))
            }
            Button {
                openURL(donateURL)
            } label: {
                Label {
                    Text(verbatim: "Support Ice".localized(for: generalSettingsManager.language))
                } icon: {
                    Image(systemName: "heart.circle.fill")
                }
            }
        }
        .padding(8)
        .buttonStyle(BottomBarButtonStyle())
        .background(.quinary, in: Capsule(style: .circular))
        .frame(height: 40)
    }
}

private struct BottomBarButtonStyle: ButtonStyle {
    @State private var isHovering = false

    private var borderShape: some InsettableShape {
        Capsule(style: .circular)
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
