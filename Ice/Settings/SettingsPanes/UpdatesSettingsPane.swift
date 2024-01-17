//
//  UpdatesSettingsPane.swift
//  Ice
//

import SwiftUI
import Sparkle

struct UpdatesSettingsPane: View {
    @EnvironmentObject var appState: AppState

    private var updatesManager: UpdatesManager {
        appState.updatesManager
    }

    private var updater: SPUUpdater {
        updatesManager.updater
    }

    var body: some View {
        Form {
            Section {
                automaticallyCheckForUpdates
            }
            if updatesManager.canCheckForUpdates {
                Section {
                    checkForUpdates
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private var automaticallyCheckForUpdates: some View {
        Toggle(
            isOn: Binding(
                get: { updater.automaticallyChecksForUpdates },
                set: { updater.automaticallyChecksForUpdates = $0 }
            )
        ) {
            Text("Automatically check for updates")
        }
    }

    @ViewBuilder
    private var checkForUpdates: some View {
        HStack {
            Spacer()
            Button("Check for Updates…") {
                updatesManager.checkForUpdates()
            }
            .controlSize(.large)
            Spacer()
        }
    }
}

#Preview {
    UpdatesSettingsPane()
        .fixedSize()
        .buttonStyle(.custom)
        .environmentObject(AppState.shared)
}
