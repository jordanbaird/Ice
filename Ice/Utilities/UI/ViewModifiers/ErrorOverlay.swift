//
//  ErrorOverlay.swift
//  Ice
//

import SwiftUI

private struct ErrorPreferenceKey<E: Error & Equatable>: PreferenceKey {
    static var defaultValue: E? { nil }

    static func reduce(value: inout E?, nextValue: () -> E?) {
        value = value ?? nextValue()
    }
}

private struct ErrorOverlayView<E: Error & Equatable, Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme: ColorScheme
    @State private var error: E?
    private let content: Content

    init(type _: E.Type, content: Content) {
        self.content = content
    }

    var body: some View {
        ZStack {
            content
            GeometryReader { proxy in
                if error != nil {
                    overlay(in: proxy.frame(in: .local))
                }
            }
        }
        .onPreferenceChange(ErrorPreferenceKey<E>.self) { error in
            if self.error == nil || error == nil {
                withAnimation {
                    self.error = error
                }
            } else {
                withAnimation(.easeInOut(duration: 0.25), completionCriteria: .removed) {
                    self.error = nil
                } completion: {
                    withAnimation {
                        self.error = error
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func overlay(in frame: CGRect) -> some View {
        Text(error?.localizedDescription ?? "")
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Material.regular,
                in: RoundedRectangle(cornerRadius: 7)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .inset(by: colorScheme == .dark ? 1.5 : 0.5)
                    .stroke(lineWidth: 1)
                    .foregroundStyle(.tertiary)
                    .opacity(0.75)
            }
            .shadow(
                color: .black.opacity(0.5),
                radius: 10
            )
            .frame(
                maxWidth: frame.width * 0.75,
                maxHeight: frame.height * 0.75
            )
            .position(
                x: frame.midX,
                y: frame.maxY - 25
            )
    }
}

extension View {
    /// Presents a descriptive overlay when errors of the given type
    /// occur.
    ///
    /// The overlay can be triggered by setting an error of the same
    /// type using the ``overlay(error:)`` modifier elsewhere in the
    /// view hierarchy.
    ///
    /// - Parameter type: The type of error to display a descriptive
    ///   overlay for.
    func errorOverlay<E: Error & Equatable>(for type: E.Type) -> some View {
        ErrorOverlayView(type: type, content: self)
    }

    /// Sets an error to be presented as a descriptive overlay atop
    /// views that have applied the ``errorOverlay(for:)`` modifier
    /// with the same type as the provided error.
    ///
    /// - Parameter error: An error to display as a descriptive
    ///   overlay. Pass `nil` to remove an existing overlay.
    func overlay<E: Error & Equatable>(error: E?) -> some View {
        preference(key: ErrorPreferenceKey<E>.self, value: error)
    }
}
