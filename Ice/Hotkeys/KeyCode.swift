//
//  KeyCode.swift
//  Ice
//

import Carbon.HIToolbox

/// Representation of a physical key on a keyboard.
struct KeyCode: Codable, Hashable, RawRepresentable {
    let rawValue: Int

    // MARK: Letters

    static let a = KeyCode(rawValue: kVK_ANSI_A)
    static let b = KeyCode(rawValue: kVK_ANSI_B)
    static let c = KeyCode(rawValue: kVK_ANSI_C)
    static let d = KeyCode(rawValue: kVK_ANSI_D)
    static let e = KeyCode(rawValue: kVK_ANSI_E)
    static let f = KeyCode(rawValue: kVK_ANSI_F)
    static let g = KeyCode(rawValue: kVK_ANSI_G)
    static let h = KeyCode(rawValue: kVK_ANSI_H)
    static let i = KeyCode(rawValue: kVK_ANSI_I)
    static let j = KeyCode(rawValue: kVK_ANSI_J)
    static let k = KeyCode(rawValue: kVK_ANSI_K)
    static let l = KeyCode(rawValue: kVK_ANSI_L)
    static let m = KeyCode(rawValue: kVK_ANSI_M)
    static let n = KeyCode(rawValue: kVK_ANSI_N)
    static let o = KeyCode(rawValue: kVK_ANSI_O)
    static let p = KeyCode(rawValue: kVK_ANSI_P)
    static let q = KeyCode(rawValue: kVK_ANSI_Q)
    static let r = KeyCode(rawValue: kVK_ANSI_R)
    static let s = KeyCode(rawValue: kVK_ANSI_S)
    static let t = KeyCode(rawValue: kVK_ANSI_T)
    static let u = KeyCode(rawValue: kVK_ANSI_U)
    static let v = KeyCode(rawValue: kVK_ANSI_V)
    static let w = KeyCode(rawValue: kVK_ANSI_W)
    static let x = KeyCode(rawValue: kVK_ANSI_X)
    static let y = KeyCode(rawValue: kVK_ANSI_Y)
    static let z = KeyCode(rawValue: kVK_ANSI_Z)

    // MARK: Numbers

    static let zero = KeyCode(rawValue: kVK_ANSI_0)
    static let one = KeyCode(rawValue: kVK_ANSI_1)
    static let two = KeyCode(rawValue: kVK_ANSI_2)
    static let three = KeyCode(rawValue: kVK_ANSI_3)
    static let four = KeyCode(rawValue: kVK_ANSI_4)
    static let five = KeyCode(rawValue: kVK_ANSI_5)
    static let six = KeyCode(rawValue: kVK_ANSI_6)
    static let seven = KeyCode(rawValue: kVK_ANSI_7)
    static let eight = KeyCode(rawValue: kVK_ANSI_8)
    static let nine = KeyCode(rawValue: kVK_ANSI_9)

    // MARK: Symbols

    static let equal = KeyCode(rawValue: kVK_ANSI_Equal)
    static let minus = KeyCode(rawValue: kVK_ANSI_Minus)
    static let rightBracket = KeyCode(rawValue: kVK_ANSI_RightBracket)
    static let leftBracket = KeyCode(rawValue: kVK_ANSI_LeftBracket)
    static let quote = KeyCode(rawValue: kVK_ANSI_Quote)
    static let semicolon = KeyCode(rawValue: kVK_ANSI_Semicolon)
    static let backslash = KeyCode(rawValue: kVK_ANSI_Backslash)
    static let comma = KeyCode(rawValue: kVK_ANSI_Comma)
    static let slash = KeyCode(rawValue: kVK_ANSI_Slash)
    static let period = KeyCode(rawValue: kVK_ANSI_Period)
    static let grave = KeyCode(rawValue: kVK_ANSI_Grave)

    // MARK: Keypad

    static let keypad0 = KeyCode(rawValue: kVK_ANSI_Keypad0)
    static let keypad1 = KeyCode(rawValue: kVK_ANSI_Keypad1)
    static let keypad2 = KeyCode(rawValue: kVK_ANSI_Keypad2)
    static let keypad3 = KeyCode(rawValue: kVK_ANSI_Keypad3)
    static let keypad4 = KeyCode(rawValue: kVK_ANSI_Keypad4)
    static let keypad5 = KeyCode(rawValue: kVK_ANSI_Keypad5)
    static let keypad6 = KeyCode(rawValue: kVK_ANSI_Keypad6)
    static let keypad7 = KeyCode(rawValue: kVK_ANSI_Keypad7)
    static let keypad8 = KeyCode(rawValue: kVK_ANSI_Keypad8)
    static let keypad9 = KeyCode(rawValue: kVK_ANSI_Keypad9)
    static let keypadDecimal = KeyCode(rawValue: kVK_ANSI_KeypadDecimal)
    static let keypadMultiply = KeyCode(rawValue: kVK_ANSI_KeypadMultiply)
    static let keypadPlus = KeyCode(rawValue: kVK_ANSI_KeypadPlus)
    static let keypadClear = KeyCode(rawValue: kVK_ANSI_KeypadClear)
    static let keypadDivide = KeyCode(rawValue: kVK_ANSI_KeypadDivide)
    static let keypadEnter = KeyCode(rawValue: kVK_ANSI_KeypadEnter)
    static let keypadMinus = KeyCode(rawValue: kVK_ANSI_KeypadMinus)
    static let keypadEquals = KeyCode(rawValue: kVK_ANSI_KeypadEquals)

    // MARK: Editing

    static let space = KeyCode(rawValue: kVK_Space)
    static let tab = KeyCode(rawValue: kVK_Tab)
    static let `return` = KeyCode(rawValue: kVK_Return)
    static let delete = KeyCode(rawValue: kVK_Delete)
    static let forwardDelete = KeyCode(rawValue: kVK_ForwardDelete)

    // MARK: Modifiers

    static let control = KeyCode(rawValue: kVK_Control)
    static let option = KeyCode(rawValue: kVK_Option)
    static let shift = KeyCode(rawValue: kVK_Shift)
    static let command = KeyCode(rawValue: kVK_Command)
    static let rightControl = KeyCode(rawValue: kVK_RightControl)
    static let rightOption = KeyCode(rawValue: kVK_RightOption)
    static let rightShift = KeyCode(rawValue: kVK_RightShift)
    static let rightCommand = KeyCode(rawValue: kVK_RightCommand)
    static let capsLock = KeyCode(rawValue: kVK_CapsLock)
    static let function = KeyCode(rawValue: kVK_Function)

    // MARK: Function

    static let f1 = KeyCode(rawValue: kVK_F1)
    static let f2 = KeyCode(rawValue: kVK_F2)
    static let f3 = KeyCode(rawValue: kVK_F3)
    static let f4 = KeyCode(rawValue: kVK_F4)
    static let f5 = KeyCode(rawValue: kVK_F5)
    static let f6 = KeyCode(rawValue: kVK_F6)
    static let f7 = KeyCode(rawValue: kVK_F7)
    static let f8 = KeyCode(rawValue: kVK_F8)
    static let f9 = KeyCode(rawValue: kVK_F9)
    static let f10 = KeyCode(rawValue: kVK_F10)
    static let f11 = KeyCode(rawValue: kVK_F11)
    static let f12 = KeyCode(rawValue: kVK_F12)
    static let f13 = KeyCode(rawValue: kVK_F13)
    static let f14 = KeyCode(rawValue: kVK_F14)
    static let f15 = KeyCode(rawValue: kVK_F15)
    static let f16 = KeyCode(rawValue: kVK_F16)
    static let f17 = KeyCode(rawValue: kVK_F17)
    static let f18 = KeyCode(rawValue: kVK_F18)
    static let f19 = KeyCode(rawValue: kVK_F19)
    static let f20 = KeyCode(rawValue: kVK_F20)

    // MARK: Navigation

    static let pageUp = KeyCode(rawValue: kVK_PageUp)
    static let pageDown = KeyCode(rawValue: kVK_PageDown)
    static let home = KeyCode(rawValue: kVK_Home)
    static let end = KeyCode(rawValue: kVK_End)
    static let escape = KeyCode(rawValue: kVK_Escape)
    static let help = KeyCode(rawValue: kVK_Help)
    static let leftArrow = KeyCode(rawValue: kVK_LeftArrow)
    static let rightArrow = KeyCode(rawValue: kVK_RightArrow)
    static let downArrow = KeyCode(rawValue: kVK_DownArrow)
    static let upArrow = KeyCode(rawValue: kVK_UpArrow)

    // MARK: Media

    static let volumeUp = KeyCode(rawValue: kVK_VolumeUp)
    static let volumeDown = KeyCode(rawValue: kVK_VolumeDown)
    static let mute = KeyCode(rawValue: kVK_Mute)
}

// MARK: Key Equivalent
extension KeyCode {
    /// System representation.
    var keyEquivalent: String {
        guard
            let inputSource = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
            let layoutData = TISGetInputSourceProperty(inputSource, kTISPropertyUnicodeKeyLayoutData)
        else {
            return ""
        }

        let layoutBytes = CFDataGetBytePtr(unsafeBitCast(layoutData, to: CFData.self))
        let layoutPtr = unsafeBitCast(layoutBytes, to: UnsafePointer<UCKeyboardLayout>.self)

        let modifierKeyState: UInt32 = 0 // empty modifier key state
        var deadKeyState: UInt32 = 0
        let maxLength = 4
        var actualLength = 0
        var codeUnits = [UniChar](repeating: 0, count: maxLength)

        let status = UCKeyTranslate(
            layoutPtr,
            UInt16(rawValue),
            UInt16(kUCKeyActionDisplay),
            modifierKeyState,
            UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            maxLength,
            &actualLength,
            &codeUnits
        )

        guard status == noErr else {
            return ""
        }

        return String(utf16CodeUnits: codeUnits, count: actualLength)
    }
}

// MARK: Custom String Mappings
private let customStringMappings = [
    // standard keys
    KeyCode.space: "Space",
    KeyCode.tab: "⇥",
    KeyCode.return: "⏎",
    KeyCode.delete: "⌫",
    KeyCode.forwardDelete: "⌦",
    KeyCode.f1: "F1",
    KeyCode.f2: "F2",
    KeyCode.f3: "F3",
    KeyCode.f4: "F4",
    KeyCode.f5: "F5",
    KeyCode.f6: "F6",
    KeyCode.f7: "F7",
    KeyCode.f8: "F8",
    KeyCode.f9: "F9",
    KeyCode.f10: "F10",
    KeyCode.f11: "F11",
    KeyCode.f12: "F12",
    KeyCode.f13: "F13",
    KeyCode.f14: "F14",
    KeyCode.f15: "F15",
    KeyCode.f16: "F16",
    KeyCode.f17: "F17",
    KeyCode.f18: "F18",
    KeyCode.f19: "F19",
    KeyCode.f20: "F20",
    KeyCode.pageUp: "⇞",
    KeyCode.pageDown: "⇟",
    KeyCode.home: "↖",
    KeyCode.end: "↘",
    KeyCode.escape: "⎋",
    KeyCode.leftArrow: "←",
    KeyCode.rightArrow: "→",
    KeyCode.downArrow: "↓",
    KeyCode.upArrow: "↑",
    KeyCode.capsLock: "⇪",
    KeyCode.control: "⌃",
    KeyCode.option: "⌥",
    KeyCode.shift: "⇧",
    KeyCode.command: "⌘",
    KeyCode.rightControl: "⌃",
    KeyCode.rightOption: "⌥",
    KeyCode.rightShift: "⇧",
    KeyCode.rightCommand: "⌘",
    KeyCode.keypadClear: "⌧",
    KeyCode.keypadEnter: "⌤",
    // media keys
    KeyCode.volumeUp: "\u{1F50A}",   // 'SPEAKER WITH THREE SOUND WAVES'
    KeyCode.volumeDown: "\u{1F509}", // 'SPEAKER WITH ONE SOUND WAVE'
    KeyCode.mute: "\u{1F507}",       // 'SPEAKER WITH CANCELLATION STROKE'
    // keypad keys
    KeyCode.keypad0: "0⃣",
    KeyCode.keypad1: "1⃣",
    KeyCode.keypad2: "2⃣",
    KeyCode.keypad3: "3⃣",
    KeyCode.keypad4: "4⃣",
    KeyCode.keypad5: "5⃣",
    KeyCode.keypad6: "6⃣",
    KeyCode.keypad7: "7⃣",
    KeyCode.keypad8: "8⃣",
    KeyCode.keypad9: "9⃣",
    KeyCode.keypadDecimal: ".⃣",
    KeyCode.keypadDivide: "/⃣",
    KeyCode.keypadEquals: "=⃣",
    KeyCode.keypadMinus: "-⃣",
    KeyCode.keypadMultiply: "*⃣",
    KeyCode.keypadPlus: "+⃣",
    // other keys
    KeyCode.function: "🌐︎︎",
    KeyCode.help: "?⃝",
]

// MARK: String Value
extension KeyCode {
    /// A custom string representation for the key.
    var stringValue: String {
        customStringMappings[self, default: keyEquivalent]
    }
}
