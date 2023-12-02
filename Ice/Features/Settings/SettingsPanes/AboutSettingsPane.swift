//
//  AboutSettingsPane.swift
//  Ice
//

import SwiftUI

struct AboutSettingsPane: View {
    @Environment(\.openURL) private var openURL

    var acknowledgementsURL: URL {
        // swiftlint:disable:next force_unwrapping
        Bundle.main.url(forResource: "Acknowledgements", withExtension: "pdf")!
    }

    var contributeURL: URL {
        // swiftlint:disable:next force_unwrapping
        URL(string: "https://github.com/jordanbaird/Ice")!
    }

    var issuesURL: URL {
        contributeURL.appendingPathComponent("issues")
    }

    var body: some View {
        HStack {
            if let nsImage = NSImage(named: NSImage.applicationIconName) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 300, height: 300)
            }

            VStack(alignment: .leading) {
                Text(Constants.appName)
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
        .frame(maxHeight: .infinity)
        .bottomBar {
            HStack {
                Button("Acknowledgements") {
                    NSWorkspace.shared.open(acknowledgementsURL)
                }
                Spacer()
                Button("Contribute") {
                    openURL(contributeURL)
                }
                Button("Report a Bug") {
                    openURL(issuesURL)
                }
            }
            .padding()
        }
    }
}

#Preview {
    AboutSettingsPane()
        .buttonStyle(.custom)
}
