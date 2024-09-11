//
//  PermissionsView.swift
//  Ice
//

import SwiftUI

struct PermissionsView: View {
    @EnvironmentObject var permissionsManager: PermissionsManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            headerView
                .padding(.vertical)

            explanationView
            permissionsGroupStack

            footerView
                .padding(.vertical)
        }
        .padding(.horizontal)
        .fixedSize()
        .readWindow { window in
            guard let window else {
                return
            }
            window.styleMask.remove([.closable, .miniaturizable])
            if let contentView = window.contentView {
                with(contentView.safeAreaInsets) { insets in
                    insets.bottom = -insets.bottom
                    insets.left = -insets.left
                    insets.right = -insets.right
                    insets.top = -insets.top
                    contentView.additionalSafeAreaInsets = insets
                }
            }
        }
    }

    @ViewBuilder
    private var headerView: some View {
        Label {
            Text("Permissions")
                .font(.system(size: 36))
        } icon: {
            if let nsImage = NSImage(named: NSImage.applicationIconName) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 75, height: 75)
            }
        }
    }

    @ViewBuilder
    private var explanationView: some View {
        GroupBox {
            VStack {
                Text("Ice needs permission to manage the menu bar.")
                Text("Absolutely no personal information is collected or stored.")
                    .bold()
                    .foregroundStyle(.red)
            }
            .padding()
        }
        .font(.title3)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var permissionsGroupStack: some View {
        VStack(spacing: 7.5) {
            permissionBox(permissionsManager.accessibilityPermission)
            permissionBox(permissionsManager.screenRecordingPermission)
        }
    }

    @ViewBuilder
    private var footerView: some View {
        HStack {
            quitButton
            continueButton
        }
        .controlSize(.large)
    }

    @ViewBuilder
    private var quitButton: some View {
        Button {
            NSApp.terminate(nil)
        } label: {
            Text("Quit")
                .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var continueButton: some View {
        Button {
            permissionsManager.appState?.performSetup()
            openWindow(id: Constants.settingsWindowID)
        } label: {
            Text("Continue")
                .frame(maxWidth: .infinity)
        }
        .disabled(!permissionsManager.hasPermission)
    }

    @ViewBuilder
    private func permissionBox(_ permission: Permission) -> some View {
        GroupBox {
            VStack(spacing: 10) {
                Text(permission.title)
                    .font(.title)
                    .underline()

                VStack(spacing: 0) {
                    Text("Ice needs this permission to:")
                        .font(.title3)
                        .bold()

                    VStack(alignment: .leading) {
                        ForEach(permission.details, id: \.self) { detail in
                            HStack {
                                Text("•").bold()
                                Text(detail)
                            }
                        }
                    }
                }

                Button {
                    permission.runWithCompletion {
                        openWindow(id: Constants.permissionsWindowID)
                    }
                } label: {
                    if permission.hasPermission {
                        Text("Permission Granted")
                            .foregroundStyle(.green)
                    } else {
                        Text("Grant Permission")
                    }
                }
                .allowsHitTesting(!permission.hasPermission)
            }
            .padding(10)
            .frame(maxWidth: .infinity)
        }
    }
}
