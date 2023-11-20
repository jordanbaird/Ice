//
//  ControlItemImageSet.swift
//  Ice
//

import Foundation

struct ControlItemImageSet: Codable, Hashable, Identifiable {
    enum Name: String, Codable, Hashable {
        case arrow = "Arrow"
        case chevron = "Chevron"
        case door = "Door"
        case dot = "Dot"
        case ellipsis = "Ellipsis"
        case iceCube = "Ice Cube"
        case sunglasses = "Sunglasses"
        case custom = "Custom"
    }

    let name: Name
    let hidden: ControlItemImage
    let visible: ControlItemImage

    var id: Int { hashValue }
}

extension ControlItemImageSet {
    static let arrow = ControlItemImageSet(
        name: .arrow,
        hidden: .symbol("arrowshape.left.fill"),
        visible: .symbol("arrowshape.right.fill")
    )

    static let chevron = ControlItemImageSet(
        name: .chevron,
        hidden: .symbol("chevron.left"),
        visible: .symbol("chevron.right")
    )

    static let door = ControlItemImageSet(
        name: .door,
        hidden: .symbol("door.left.hand.closed"),
        visible: .symbol("door.left.hand.open")
    )

    static let dot = ControlItemImageSet(
        name: .dot,
        hidden: .builtin(.dotFilled),
        visible: .builtin(.dotStroked)
    )

    static let ellipsis = ControlItemImageSet(
        name: .ellipsis,
        hidden: .catalog("EllipsisFill"),
        visible: .catalog("EllipsisStroke")
    )

    static let iceCube = ControlItemImageSet(
        name: .iceCube,
        hidden: .catalog("IceCube"),
        visible: .catalog("IceCube")
    )

    static let sunglasses = ControlItemImageSet(
        name: .sunglasses,
        hidden: .symbol("sunglasses.fill"),
        visible: .symbol("sunglasses")
    )

    static let userSelectableImageSets: [ControlItemImageSet] = {
        var imageSets: Set<ControlItemImageSet> = [
            arrow,
            chevron,
            door,
            dot,
            ellipsis,
            iceCube,
            sunglasses,
        ]
        if let data = UserDefaults.standard.data(forKey: Defaults.iceIcon) {
            let decoder = JSONDecoder()
            if let iceIcon = try? decoder.decode(ControlItemImageSet.self, from: data) {
                imageSets.insert(iceIcon)
            }
        }
        return imageSets.sorted { lhs, rhs in
            lhs.name.rawValue < rhs.name.rawValue
        }
    }()
}
