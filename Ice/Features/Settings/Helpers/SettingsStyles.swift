//
//  SettingsStyles.swift
//  Ice
//

import SwiftUI

// MARK: - SettingsButtonID

/// An identifier that determines the shape that a settings
/// button is rendered with.
struct SettingsButtonID {
    fileprivate let flattenedEdges: Edge.Set

    /// An identifier that will render a settings button with
    /// the default shape.
    static let `default` = SettingsButtonID(flattenedEdges: [])
    /// An identifier that will render a settings button with
    /// the shape of a leading segment in a segmented control.
    static let leadingSegment = SettingsButtonID(flattenedEdges: .trailing)
    /// An identifier that will render a settings button with
    /// the shape of a trailing segment in a segmented control.
    static let trailingSegment = SettingsButtonID(flattenedEdges: .leading)
}

private extension EnvironmentValues {
    struct SettingsButtonIDKey: EnvironmentKey {
        static let defaultValue: SettingsButtonID = .default
    }

    var settingsButtonID: SettingsButtonID {
        get { self[SettingsButtonIDKey.self] }
        set { self[SettingsButtonIDKey.self] = newValue }
    }
}

extension View {
    /// Sets the identifier for settings buttons in this view.
    func settingsButtonID(_ id: SettingsButtonID) -> some View {
        environment(\.settingsButtonID, id)
    }
}

// MARK: - SettingsButtonStyle

/// The button style to use in the "Settings" interface.
struct SettingsButtonStyle: PrimitiveButtonStyle {
    /// Custom shape that draws a rounded rectangle with some of its
    /// sides flattened according to the given id.
    private struct ClipShape: Shape {
        let cornerRadius: CGFloat
        let id: SettingsButtonID

        func path(in rect: CGRect) -> Path {
            if id.flattenedEdges == .all {
                // fast path (pun not intended)
                return Path(rect)
            }
            var path = Path(roundedRect: rect, cornerRadius: cornerRadius, style: .continuous)
            if id.flattenedEdges.isEmpty {
                // fast path MkII
                return path
            }
            for edge in Edge.allCases where id.flattenedEdges.contains(Edge.Set(edge)) {
                flatten(edge: edge, of: &path)
            }
            return path
        }

        func flatten(edge: Edge, of path: inout Path) {
            let (rect, distance, edge) = (path.boundingRect, cornerRadius, edge.cgRectEdge)
            let slice = rect.divided(atDistance: distance, from: edge).slice
            path = Path(path.cgPath.union(Path(slice).cgPath))
        }
    }

    @State private var isPressed = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 10)
            .padding(.vertical, 2.5)
            .baselineOffset(1)
            .transformEnvironment(\.font) { font in
                if font == nil {
                    font = .body.weight(.medium)
                }
            }
            .backgroundEnvironmentValue(\.settingsButtonID) { id in
                VisualEffectView(
                    material: .contentBackground,
                    blendingMode: .withinWindow,
                    isEmphasized: true
                )
                .opacity(0.5)
                .background(isPressed ? .secondary : .tertiary)
                .clipShape(ClipShape(cornerRadius: 5, id: id))
            }
            .interceptMouseDown()
            .onContinuousPress { info in
                isPressed = info.frame.contains(info.location)
            } onEnded: { info in
                isPressed = false
                if info.frame.contains(info.location) {
                    configuration.trigger()
                }
            }
    }
}

// MARK: - SettingsToggleStyle

struct SettingsToggleStyle: ToggleStyle {
    @State private var isPressed = false

    func makeBody(configuration: Configuration) -> some View {
        HStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .inset(by: 0.5)
                .stroke(lineWidth: 1)
                .foregroundStyle(.tertiary)
                .overlay(
                    Image(systemName: configuration.isMixed ? "minus" : "checkmark")
                        .resizable()
                        .opacity(configuration.isOn ? 1 : 0)
                        .aspectRatio(contentMode: .fit)
                        .fontWeight(.heavy)
                        .padding(3)
                )
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(.selection)
                        .opacity(isPressed ? 0.5 : 0)
                )
                .frame(width: 14, height: 14)

            configuration.label
        }
        .contentShape(Rectangle())
        .interceptMouseDown()
        .onContinuousPress { info in
            isPressed = info.frame.contains(info.location)
        } onEnded: { info in
            isPressed = false
            if info.frame.contains(info.location) {
                configuration.isOn.toggle()
            }
        }
    }
}
