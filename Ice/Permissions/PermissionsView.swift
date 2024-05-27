//
//  PermissionsView.swift
//  Ice
//

import SwiftUI

struct PermissionsView: View {
    @EnvironmentObject var appState: AppState

    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openWindow) private var openWindow

    let onContinue: () -> Void

    private var permissionsManager: PermissionsManager {
        appState.permissionsManager
    }

    var body: some View {
        VStack {
            headerView
            explanationView
            permissionsGroupStack
            footerView
        }
        .fixedSize()
        .padding()
    }

    @ViewBuilder
    private var headerView: some View {
        Label {
            Text("Permissions")
                .font(.system(size: 30))
        } icon: {
            if let nsImage = NSImage(named: NSImage.applicationIconName) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 50, height: 50)
            }
        }
    }

    @ViewBuilder
    private var explanationView: some View {
        VStack {
            Text("Ice needs your permission to manage your menu bar.")
            Text("Absolutely no personal information is collected or stored.")
                .bold()
                .underline()
        }
    }

    @ViewBuilder
    private var permissionsGroupStack: some View {
        VStack {
            permissionBox(permissionsManager.accessibilityPermission)
            permissionBox(permissionsManager.screenRecordingPermission)
        }
    }

    @ViewBuilder
    private var footerView: some View {
        Button {
            dismissWindow()
            onContinue()
        } label: {
            Text("Continue")
                .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
        .opacity(permissionsManager.hasPermission ? 1 : 0)
        .disabled(!permissionsManager.hasPermission)
    }

    @ViewBuilder
    private func permissionBox(_ permission: Permission) -> some View {
        GroupBox {
            VStack(spacing: 2) {
                Text(permission.title)
                    .font(.title)
                    .underline()

                Text("\(Constants.appName) needs your permission to:")
                    .font(.subheadline)

                VStack(alignment: .leading) {
                    ForEach(permission.details, id: \.self) { detail in
                        Text(detail)
                    }
                }

                VStack(spacing: 1) {
                    ForEach(permission.notes, id: \.self) { note in
                        Text(note)
                            .bold()
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background {
                                RoundedRectangle(
                                    cornerRadius: 5,
                                    style: .circular
                                )
                                .fill(.quinary)
                            }
                    }
                }
                .padding(3)

                if permission.hasPermission {
                    Label(
                        "\(Constants.appName) has been granted permission",
                        systemImage: "checkmark"
                    )
                    .foregroundStyle(.green)
                    .symbolVariant(.circle.fill)
                    .focusable(false)
                    .frame(height: 21)
                } else {
                    Button("Grant Permission") {
                        permission.runWithCompletion {
                            openWindow(id: Constants.permissionsWindowID)
                        }
                    }
                    .frame(height: 21)
                }
            }
            .padding(5)
            .frame(maxWidth: .infinity)
        }
    }
}

#Preview {
    PermissionsView { }
        .environmentObject(AppState.shared)
}
