//
//  DismissWindowButton.swift
//  Ice
//

import SwiftUI

struct DismissWindowButton<Label: View>: View {
    @State private var dismissWindow: (() -> Void)?

    private let label: Label

    init(@ViewBuilder label: () -> Label) {
        self.label = label()
    }

    init(_ titleKey: LocalizedStringKey) where Label == Text {
        self.label = Text(titleKey)
    }

    private var role: ButtonRole? {
        if #available(macOS 26.0, *) {
            return .close
        } else {
            return nil
        }
    }

    var body: some View {
        Button(role: role) {
            dismissWindow?()
        } label: {
            label
        }
        .onWindowChange { window in
            updateAction(with: window)
        }
    }

    private func updateAction(with window: NSWindow?) {
        guard let window else {
            dismissWindow = nil
            return
        }
        dismissWindow = { [weak window] in
            window?.close()
        }
    }
}
