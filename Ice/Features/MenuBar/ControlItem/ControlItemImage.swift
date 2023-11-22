//
//  ControlItemImage.swift
//  Ice
//

import Cocoa

/// A Codable image for a control item.
enum ControlItemImage: Codable, Hashable {
    /// An image created from drawing code in the app.
    case builtin(_ name: ImageBuiltinName)
    /// A system symbol image.
    case symbol(_ name: String)
    /// An image in an asset catalog.
    case catalog(_ name: String)
    /// An image stored as data.
    case data(_ data: Data)

    /// A Cocoa representation of this image.
    func nsImage(for menuBar: MenuBar) -> NSImage? {
        switch self {
        case .builtin(let name):
            return switch name {
            case .dotFilled: StaticBuiltins.Dot.filled
            case .dotStroked: StaticBuiltins.Dot.stroked
            case .chevronLarge: StaticBuiltins.Chevron.large
            case .chevronSmall: StaticBuiltins.Chevron.small
            }
        case .symbol(let name):
            let image = NSImage(systemSymbolName: name, accessibilityDescription: "")
            image?.isTemplate = true
            return image
        case .catalog(let name):
            return NSImage(named: name)
        case .data(let data):
            let image = NSImage(data: data)
            image?.isTemplate = menuBar.customIceIconIsTemplate
            return image
        }
    }
}

extension ControlItemImage {
    /// A name for an image that is created from drawing code
    /// in the app.
    enum ImageBuiltinName: Codable, Hashable {
        /// A filled dot.
        case dotFilled
        /// A stroked dot.
        case dotStroked
        /// A large chevron.
        case chevronLarge
        /// A small chevron.
        case chevronSmall
    }
}

extension ControlItemImage {
    /// A namespace for static builtin images.
    ///
    /// - Note: We use static properties to avoid repeatedly
    ///   executing code every time the ``nsImage`` property
    ///   is accessed.
    private enum StaticBuiltins {
        /// A namespace for static builtin dot images.
        enum Dot {
            /// A filled dot.
            static let filled: NSImage = {
                let image = NSImage(size: CGSize(width: 8, height: 8), flipped: false) { bounds in
                    NSColor.black.setFill()
                    NSBezierPath(ovalIn: bounds).fill()
                    return true
                }
                image.isTemplate = true
                return image
            }()

            /// A stroked dot.
            static let stroked: NSImage = {
                let image = NSImage(size: CGSize(width: 8, height: 8), flipped: false) { bounds in
                    let lineWidth: CGFloat = 1.5
                    let insetBounds = bounds.insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
                    let path = NSBezierPath(ovalIn: insetBounds)
                    path.lineWidth = lineWidth
                    NSColor.black.setStroke()
                    path.stroke()
                    return true
                }
                image.isTemplate = true
                return image
            }()
        }

        /// A namespace for static builtin chevron images.
        enum Chevron {
            /// Creates a chevron image with the given size and line width.
            private static func chevron(size: CGSize, lineWidth: CGFloat) -> NSImage {
                let image = NSImage(size: size, flipped: false) { bounds in
                    let insetBounds = bounds.insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
                    let path = NSBezierPath()
                    path.move(to: CGPoint(x: (insetBounds.midX + insetBounds.maxX) / 2, y: insetBounds.maxY))
                    path.line(to: CGPoint(x: (insetBounds.minX + insetBounds.midX) / 2, y: insetBounds.midY))
                    path.line(to: CGPoint(x: (insetBounds.midX + insetBounds.maxX) / 2, y: insetBounds.minY))
                    path.lineWidth = lineWidth
                    path.lineCapStyle = .butt
                    NSColor.black.setStroke()
                    path.stroke()
                    return true
                }
                image.isTemplate = true
                return image
            }

            /// A large chevron.
            static let large = chevron(size: CGSize(width: 12, height: 12), lineWidth: 2)

            /// A small chevron.
            static let small = chevron(size: CGSize(width: 9, height: 9), lineWidth: 2)
        }
    }
}
