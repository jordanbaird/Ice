import SwiftUI

struct InitialLanguageView: View {
    @State private var language = AppLanguage.current()

    var body: some View {
        VStack(spacing: 24) {
            if let icon = NSImage(named: NSImage.applicationIconName) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 80, height: 80)
            }
            Text("Choose Your Language", bundle: language.previewBundle)
                .font(.title2.bold())
            Text("Choose a language before setting up permissions.", bundle: language.previewBundle)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Picker(selection: $language) {
                ForEach(AppLanguage.allCases) { option in
                    if option == .system {
                        Text("Follow System", bundle: language.previewBundle).tag(option)
                    } else {
                        Text(verbatim: option.displayName).tag(option)
                    }
                }
            } label: {
                Text("Language", bundle: language.previewBundle)
            }
            .pickerStyle(.menu)

            Text("Ice will reopen to apply a different language.", bundle: language.previewBundle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack {
                Button {
                    NSApp.terminate(nil)
                } label: {
                    Text("Quit", bundle: language.previewBundle)
                }
                Spacer()
                Button {
                    LanguageManager.shared.completeInitialSetup(with: language)
                } label: {
                    Text("Next", bundle: language.previewBundle)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(30)
        .environment(\.locale, Locale(identifier: language.resolvedIdentifier))
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .readWindow { window in
            window?.styleMask.remove([.closable, .miniaturizable])
        }
    }
}
