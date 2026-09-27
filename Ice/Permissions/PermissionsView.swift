//
//  PermissionsView.swift
//  Ice
//

import SwiftUI

struct PermissionsView: View {
    @EnvironmentObject var permissionsManager: PermissionsManager
    @State private var requestedPermission: Permission?

    private var continueButtonText: LocalizedStringKey {
        if case .hasRequiredPermissions = permissionsManager.permissionsState {
            "Continue in Limited Mode"
        } else {
            "Continue"
        }
    }

    private var continueButtonForegroundStyle: some ShapeStyle {
        if case .hasRequiredPermissions = permissionsManager.permissionsState {
            AnyShapeStyle(.yellow)
        } else {
            AnyShapeStyle(.primary)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView
                .padding(.vertical)

            explanationView
            permissionsGroupStack

            permissionHelp
                .padding(.top, 12)

            footerView
                .padding(.vertical)
        }
        .padding(.horizontal)
        .fixedSize()
        .onAppear {
            permissionsManager.startAllChecks()
        }
        .onReceive(permissionsManager.$permissionsState) { _ in
            guard requestedPermission?.hasPermission == true else { return }
            requestedPermission = nil
            permissionsManager.appState?.activate(withPolicy: .regular)
        }
        .onDisappear {
            requestedPermission = nil
        }
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

    private var permissionHelp: some View {
        VStack(spacing: 8) {
            if permissionsManager.permissionsState == .missingPermissions {
                Text("Accessibility permission is required to continue. Screen Recording is a separate permission.")
                    .foregroundStyle(.orange)
            }
            Text("Already enabled? Restart Ice. If it still shows as denied, remove the old Ice entry in System Settings and add this copy again.")
                .foregroundStyle(.secondary)
            HStack {
                Button("Refresh Permissions") {
                    permissionsManager.refreshAll()
                }
                Button("Restart Ice") {
                    LanguageManager.shared.restart()
                }
                Button("Show This App in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                }
            }
        }
        .font(.caption)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 450)
        .fixedSize(horizontal: false, vertical: true)
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
        IceSection {
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
            ForEach(permissionsManager.allPermissions) { permission in
                permissionBox(permission)
            }
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
            guard let appState = permissionsManager.appState else {
                return
            }
            appState.performSetup()
            appState.permissionsWindow?.close()
            appState.appDelegate?.openSettingsWindow()
        } label: {
            Text(continueButtonText)
                .frame(maxWidth: .infinity)
                .foregroundStyle(continueButtonForegroundStyle)
        }
        .disabled(permissionsManager.permissionsState == .missingPermissions)
    }

    @ViewBuilder
    private func permissionBox(_ permission: Permission) -> some View {
        IceSection {
            VStack(spacing: 10) {
                Text(permission.title)
                    .font(.title)
                    .underline()

                VStack(spacing: 0) {
                    Text("Ice needs this to:")
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
                    requestedPermission = permission
                    permission.performRequest()
                } label: {
                    if permission.hasPermission {
                        Text("Permission Granted")
                            .foregroundStyle(.green)
                    } else {
                        Text("Grant Permission")
                    }
                }
                .allowsHitTesting(!permission.hasPermission)

                if !permission.isRequired {
                    IceGroupBox {
                        AnnotationView(
                            alignment: .center,
                            font: .callout.bold()
                        ) {
                            Label {
                                Text("Ice can work in a limited mode without this permission.")
                            } icon: {
                                Image(systemName: "checkmark.shield")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity)
        }
    }
}
