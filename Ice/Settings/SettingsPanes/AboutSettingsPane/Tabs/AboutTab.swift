//
//  AboutTab.swift
//  Ice
//

import SwiftUI

struct AboutTab: View {
    @Environment(\.openURL) private var openURL
    @State private var frame: CGRect = .zero

    private var isLarge: Bool {
        frame.width >= 475
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
                    .frame(width: isLarge ? 300 : 200)
            }

            VStack(alignment: .leading) {
                Text(Constants.appName)
                    .font(.system(size: isLarge ? 64 : 36))
                    .foregroundStyle(.primary)

                HStack(spacing: 4) {
                    Text("Version")
                    Text(Constants.appVersion)
                }
                .font(.system(size: isLarge ? 16 : 12))
                .foregroundStyle(.secondary)

                Text(Constants.copyright)
                    .font(.system(size: isLarge ? 14 : 10))
                    .foregroundStyle(.tertiary)
            }
            .fontWeight(.medium)
            .padding([.vertical, .trailing])
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity
        )
        .onFrameChange(update: $frame)
        .bottomBar {
            HStack {
                Button("Quit \(Constants.appName)") {
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
                        "Support \(Constants.appName)",
                        systemImage: "heart.circle.fill"
                    )
                }
            }
            .padding()
            .customButtonConfiguration { configuration in
                configuration.labelPadding.top = 1
                configuration.labelPadding.leading = 1
                configuration.labelPadding.bottom = 1
                configuration.labelPadding.trailing = 1
                configuration.font = .body.weight(.medium)
            }
        }
    }
}
