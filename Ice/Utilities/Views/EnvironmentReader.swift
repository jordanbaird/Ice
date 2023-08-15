//
//  EnvironmentReader.swift
//  Ice
//

import SwiftUI

struct EnvironmentReader<Value, Content: View>: View {
    @Environment private var value: Value
    private let content: (Value) -> Content

    var body: some View { content(value) }

    init(_ keyPath: KeyPath<EnvironmentValues, Value>, @ViewBuilder content: @escaping (Value) -> Content) {
        self._value = Environment(keyPath)
        self.content = content
    }

    init(@ViewBuilder content: @escaping (_ environment: Value) -> Content) where Value == EnvironmentValues {
        self.init(\.self, content: content)
    }
}
