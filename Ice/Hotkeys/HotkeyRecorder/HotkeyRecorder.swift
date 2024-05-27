//
//  HotkeyRecorder.swift
//  Ice
//

import SwiftUI

struct HotkeyRecorder<Label: View>: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var model: HotkeyRecorderModel
    @State private var frame: CGRect = .zero
    @State private var timer: Timer?

    private let label: Label

    private var symbolString: String {
        if model.isRecording {
            "escape"
        } else if model.hotkey.isEnabled {
            "xmark.circle.fill"
        } else {
            "record.circle"
        }
    }

    init(hotkey: Hotkey, @ViewBuilder label: () -> Label) {
        let model = HotkeyRecorderModel(hotkey: hotkey)
        self._model = StateObject(wrappedValue: model)
        self.label = label()
    }

    var body: some View {
        LabeledContent {
            HStack(spacing: 1) {
                segment1
                segment2
            }
            .frame(width: 133, height: 22)
            .onFrameChange(update: $frame)
            .alert(
                model.presentedError?.localizedDescription ?? "",
                isPresented: $model.isPresentingError
            ) {
                Button("OK") {
                    model.isPresentingError = false
                }
            }
        } label: {
            label
        }
        .task {
            model.assignAppState(appState)
        }
    }

    @ViewBuilder
    private var segment1: some View {
        Button {
            model.startRecording()
        } label: {
            Color.clear.overlay {
                segment1Label
            }
        }
        .buttonStyle(
            SegmentButtonStyle(
                kind: .leading,
                isHighlighted: model.isRecording
            )
        )
    }

    @ViewBuilder
    private var segment2: some View {
        Button {
            if model.isRecording {
                model.stopRecording()
            } else if model.hotkey.isEnabled {
                model.hotkey.keyCombination = nil
            } else {
                model.startRecording()
            }
        } label: {
            Color.clear.overlay {
                segment2Label
            }
        }
        .buttonStyle(
            SegmentButtonStyle(
                kind: .trailing,
                isHighlighted: false
            )
        )
        .frame(width: frame.height)
    }

    @ViewBuilder
    private var segment1Label: some View {
        if model.isRecording {
            Text("Type Hotkey")
        } else if model.hotkey.isEnabled {
            if let keyCombination = model.hotkey.keyCombination {
                HStack(spacing: 0) {
                    Text(keyCombination.modifiers.symbolicValue)
                    Text(keyCombination.key.stringValue.capitalized)
                }
            }
        } else {
            Text("Record Hotkey")
        }
    }

    @ViewBuilder
    private var segment2Label: some View {
        Image(systemName: symbolString)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .padding(1)
    }
}

private struct SegmentButtonStyle: PrimitiveButtonStyle {
    enum Kind {
        case leading
        case trailing
    }

    /// A custom view that ensures that the button accepts the first mouse input.
    private struct FirstMouseOverlay: NSViewRepresentable {
        private class Represented: NSView {
            override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        }
        func makeNSView(context: Context) -> NSView { Represented() }
        func updateNSView(_: NSView, context: Context) { }
    }

    /// A custom view that adds a button to the background of the view.
    private struct ButtonView: NSViewRepresentable {
        class Represented: NSView {
            let button = NSButton(title: "", target: nil, action: nil)

            init(kind: Kind) {
                super.init(frame: .zero)

                addSubview(button)

                button.bezelStyle = .flexiblePush
                button.translatesAutoresizingMaskIntoConstraints = false

                button.widthAnchor.constraint(equalTo: widthAnchor, constant: 10).isActive = true
                button.heightAnchor.constraint(equalTo: heightAnchor).isActive = true
                button.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true

                switch kind {
                case .leading:
                    button.leadingAnchor.constraint(equalTo: leadingAnchor).isActive = true
                case .trailing:
                    button.trailingAnchor.constraint(equalTo: trailingAnchor).isActive = true
                }
            }

            @available(*, unavailable)
            required init?(coder: NSCoder) {
                fatalError("init(coder:) has not been implemented")
            }
        }

        var kind: Kind
        var isHighlighted: Bool

        func makeNSView(context: Context) -> Represented {
            Represented(kind: kind)
        }
        func updateNSView(_ nsView: Represented, context: Context) {
            nsView.button.isHighlighted = isHighlighted
        }
    }

    @State private var frame = CGRect.zero
    @State private var isPressed = false

    var kind: Kind
    var isHighlighted: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.primary)
            .padding(EdgeInsets(top: 3, leading: 8, bottom: 3, trailing: 8))
            .lineLimit(1)
            .background {
                ButtonView(kind: kind, isHighlighted: isHighlighted || isPressed)
                    .allowsHitTesting(false)
            }
            .overlay {
                FirstMouseOverlay()
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isPressed = frame.contains(value.location)
                    }
                    .onEnded { value in
                        isPressed = false
                        if frame.contains(value.location) {
                            configuration.trigger()
                        }
                    }
            )
            .offset(x: kind == .leading ? 1 : -1, y: 1)
            .clipShape(
                Rectangle()
                    .size(frame.insetBy(dx: 0, dy: -1).size)
            )
            .onFrameChange(update: $frame)
    }
}
