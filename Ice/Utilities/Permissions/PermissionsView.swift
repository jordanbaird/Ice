//
//  PermissionsView.swift
//  Ice
//

import SwiftUI

struct PermissionsView: View {
    @Binding var isPresented: Bool
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack {
            headerView
            explanationView
            permissionsGroupStack
            grantPermissionCallout
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
        VStack(spacing: 0) {
            Text("Ice needs permission to manage your menu bar.")
            Text("Absolutely no personal information is collected or stored.")
        }
    }

    @ViewBuilder
    private var permissionsGroupStack: some View {
        VStack {
            PermissionsGroupView(group: appState.permissionsManager.accessibilityGroup)
            PermissionsGroupView(group: appState.permissionsManager.screenCaptureGroup)
        }
    }

    @ViewBuilder
    private var grantPermissionCallout: some View {
        Text("Clicking \"Grant Permission\" will open System Settings")
            .font(.callout)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var footerView: some View {
        HStack(alignment: .bottom) {
            Button("Quit \(Constants.appName)") {
                isPresented = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    NSApp.terminate(self)
                }
            }
            .focusable(false)

            Spacer()

            if appState.permissionsManager.hasPermissions {
                Button("Continue") {
                    isPresented = false
//                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
//                        appState.sharedContent.activate()
//                    }
                }
            }
        }
    }
}

private struct PermissionsGroupView<Request: PermissionsRequest, Check: PermissionsCheck<Request>>: View {
    @ObservedObject var group: PermissionsGroup<Request, Check>

    var body: some View {
        GroupBox {
            VStack(spacing: 2) {
                Text(group.title)
                    .font(.title)
                    .underline()

                Text("\(Constants.appName) needs your permission to:")
                    .font(.subheadline)

                VStack(alignment: .leading) {
                    ForEach(group.details, id: \.self) { detail in
                        HStack(spacing: 5) {
                            Text("•").bold()
                            Text(detail)
                        }
                    }
                }

                VStack(spacing: 1) {
                    ForEach(group.notes, id: \.self) { note in
                        Text(note)
                            .bold()
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background {
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(.quinary)
                            }
                    }
                }
                .padding(3)

                if group.hasPermissions {
                    Label(
                        "\(Constants.appName) has the required permissions",
                        systemImage: "checkmark"
                    )
                    .foregroundStyle(.green)
                    .symbolVariant(.circle.fill)
                    .focusable(false)
                    .frame(height: 21)
                } else {
                    Button(
                        "Grant Permission",
                        action: group.performRequest
                    )
                    .frame(height: 21)
                }
            }
            .padding(5)
            .frame(maxWidth: .infinity)
        }
    }
}

#Preview {
    @State var isPresented = false

    return PermissionsView(isPresented: $isPresented)
        .buttonStyle(.custom)
        .environmentObject(AppState.shared)
}
