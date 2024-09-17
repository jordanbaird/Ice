//
//  IcePopUpIndicator.swift
//  Ice
//

import SwiftUI

struct IcePopUpIndicator: View {
    private enum ChevronKind: String {
        case up, down
    }

    enum Style {
        case popUp, pullDown
    }

    let isHovering: Bool
    let isBordered: Bool
    let style: Style

    var body: some View {
        ZStack {
            if isBordered {
                RoundedRectangle(cornerRadius: 4, style: .circular)
                    .fill(.quaternary)
                    .opacity(isHovering ? 0 : 1)
            }

            switch style {
            case .popUp:
                VStack(spacing: 2) {
                    chevron(.up)
                    chevron(.down)
                }
            case .pullDown:
                chevron(.down)
                    .offset(y: 0.5)
            }
        }
        .frame(width: 16, height: 16)
    }

    @ViewBuilder
    private func chevron(_ kind: ChevronKind) -> some View {
        Image(systemName: "chevron.\(kind.rawValue)")
            .resizable()
            .frame(width: 7.5, height: 5)
            .fontWeight(.black)
            .foregroundStyle(Color.primary)
    }
}
