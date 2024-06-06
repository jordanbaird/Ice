//
//  AboutSettingsPane.swift
//  Ice
//

import SwiftUI

struct AboutSettingsPane: View {
    @Environment(\.openURL) private var openURL

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

    private var sponsorURL: URL {
        // swiftlint:disable:next force_unwrapping
        URL(string: "https://github.com/sponsors/jordanbaird")!
    }

    var body: some View {
        HStack {
            if let nsImage = NSImage(named: NSImage.applicationIconName) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 300)
            }

            VStack(alignment: .leading) {
                Text("Ice")
                    .font(.system(size: 64))
                    .foregroundStyle(.primary)

                HStack(spacing: 4) {
                    Text("Version")
                    Text(Constants.appVersion)
                }
                .font(.system(size: 16))
                .foregroundStyle(.secondary)

                Text(Constants.copyright)
                    .font(.system(size: 14))
                    .foregroundStyle(.tertiary)
            }
            .fontWeight(.medium)
            .padding([.vertical, .trailing])
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity
        )
        .bottomBar {
            HStack {
                Button("Quit Ice") {
                    NSApp.terminate(nil)
                }
                Spacer()
                Button("Acknowledgements") {
                    NSWorkspace.shared.open(acknowledgementsURL)
                }
                Button("Contribute") {
                    openURL(contributeURL)
                }
                Button("Report a Bug") {
                    openURL(issuesURL)
                }
                Button {
                    openURL(sponsorURL)
                } label: {
                    Label(
                        "Support Ice",
                        systemImage: "heart.circle.fill"
                    )
                }
            }
            .padding()
        }
    }
}
