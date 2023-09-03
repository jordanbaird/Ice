//
//  Hotkey+Key.swift
//  Ice
//

import Carbon.HIToolbox

extension Hotkey {
    /// A representation of a physical key on a keyboard.
    struct Key: Codable, Hashable, RawRepresentable {
        let rawValue: Int

        init(rawValue: Int) {
            self.rawValue = rawValue
        }

        // MARK: Letters

        static let a = Key(rawValue: kVK_ANSI_A)
        static let b = Key(rawValue: kVK_ANSI_B)
        static let c = Key(rawValue: kVK_ANSI_C)
        static let d = Key(rawValue: kVK_ANSI_D)
        static let e = Key(rawValue: kVK_ANSI_E)
        static let f = Key(rawValue: kVK_ANSI_F)
        static let g = Key(rawValue: kVK_ANSI_G)
        static let h = Key(rawValue: kVK_ANSI_H)
        static let i = Key(rawValue: kVK_ANSI_I)
        static let j = Key(rawValue: kVK_ANSI_J)
        static let k = Key(rawValue: kVK_ANSI_K)
        static let l = Key(rawValue: kVK_ANSI_L)
        static let m = Key(rawValue: kVK_ANSI_M)
        static let n = Key(rawValue: kVK_ANSI_N)
        static let o = Key(rawValue: kVK_ANSI_O)
        static let p = Key(rawValue: kVK_ANSI_P)
        static let q = Key(rawValue: kVK_ANSI_Q)
        static let r = Key(rawValue: kVK_ANSI_R)
        static let s = Key(rawValue: kVK_ANSI_S)
        static let t = Key(rawValue: kVK_ANSI_T)
        static let u = Key(rawValue: kVK_ANSI_U)
        static let v = Key(rawValue: kVK_ANSI_V)
        static let w = Key(rawValue: kVK_ANSI_W)
        static let x = Key(rawValue: kVK_ANSI_X)
        static let y = Key(rawValue: kVK_ANSI_Y)
        static let z = Key(rawValue: kVK_ANSI_Z)

        // MARK: Numbers

        static let zero = Key(rawValue: kVK_ANSI_0)
        static let one = Key(rawValue: kVK_ANSI_1)
        static let two = Key(rawValue: kVK_ANSI_2)
        static let three = Key(rawValue: kVK_ANSI_3)
        static let four = Key(rawValue: kVK_ANSI_4)
        static let five = Key(rawValue: kVK_ANSI_5)
        static let six = Key(rawValue: kVK_ANSI_6)
        static let seven = Key(rawValue: kVK_ANSI_7)
        static let eight = Key(rawValue: kVK_ANSI_8)
        static let nine = Key(rawValue: kVK_ANSI_9)

        // MARK: Symbols

        static let equal = Key(rawValue: kVK_ANSI_Equal)
        static let minus = Key(rawValue: kVK_ANSI_Minus)
        static let rightBracket = Key(rawValue: kVK_ANSI_RightBracket)
        static let leftBracket = Key(rawValue: kVK_ANSI_LeftBracket)
        static let quote = Key(rawValue: kVK_ANSI_Quote)
        static let semicolon = Key(rawValue: kVK_ANSI_Semicolon)
        static let backslash = Key(rawValue: kVK_ANSI_Backslash)
        static let comma = Key(rawValue: kVK_ANSI_Comma)
        static let slash = Key(rawValue: kVK_ANSI_Slash)
        static let period = Key(rawValue: kVK_ANSI_Period)
        static let grave = Key(rawValue: kVK_ANSI_Grave)

        // MARK: Keypad

        static let keypad0 = Key(rawValue: kVK_ANSI_Keypad0)
        static let keypad1 = Key(rawValue: kVK_ANSI_Keypad1)
        static let keypad2 = Key(rawValue: kVK_ANSI_Keypad2)
        static let keypad3 = Key(rawValue: kVK_ANSI_Keypad3)
        static let keypad4 = Key(rawValue: kVK_ANSI_Keypad4)
        static let keypad5 = Key(rawValue: kVK_ANSI_Keypad5)
        static let keypad6 = Key(rawValue: kVK_ANSI_Keypad6)
        static let keypad7 = Key(rawValue: kVK_ANSI_Keypad7)
        static let keypad8 = Key(rawValue: kVK_ANSI_Keypad8)
        static let keypad9 = Key(rawValue: kVK_ANSI_Keypad9)
        static let keypadDecimal = Key(rawValue: kVK_ANSI_KeypadDecimal)
        static let keypadMultiply = Key(rawValue: kVK_ANSI_KeypadMultiply)
        static let keypadPlus = Key(rawValue: kVK_ANSI_KeypadPlus)
        static let keypadClear = Key(rawValue: kVK_ANSI_KeypadClear)
        static let keypadDivide = Key(rawValue: kVK_ANSI_KeypadDivide)
        static let keypadEnter = Key(rawValue: kVK_ANSI_KeypadEnter)
        static let keypadMinus = Key(rawValue: kVK_ANSI_KeypadMinus)
        static let keypadEquals = Key(rawValue: kVK_ANSI_KeypadEquals)

        // MARK: Editing

        static let space = Key(rawValue: kVK_Space)
        static let tab = Key(rawValue: kVK_Tab)
        static let `return` = Key(rawValue: kVK_Return)
        static let delete = Key(rawValue: kVK_Delete)
        static let forwardDelete = Key(rawValue: kVK_ForwardDelete)

        // MARK: Modifiers

        static let control = Key(rawValue: kVK_Control)
        static let option = Key(rawValue: kVK_Option)
        static let shift = Key(rawValue: kVK_Shift)
        static let command = Key(rawValue: kVK_Command)
        static let rightControl = Key(rawValue: kVK_RightControl)
        static let rightOption = Key(rawValue: kVK_RightOption)
        static let rightShift = Key(rawValue: kVK_RightShift)
        static let rightCommand = Key(rawValue: kVK_RightCommand)
        static let capsLock = Key(rawValue: kVK_CapsLock)
        static let function = Key(rawValue: kVK_Function)

        // MARK: Function

        static let f1 = Key(rawValue: kVK_F1)
        static let f2 = Key(rawValue: kVK_F2)
        static let f3 = Key(rawValue: kVK_F3)
        static let f4 = Key(rawValue: kVK_F4)
        static let f5 = Key(rawValue: kVK_F5)
        static let f6 = Key(rawValue: kVK_F6)
        static let f7 = Key(rawValue: kVK_F7)
        static let f8 = Key(rawValue: kVK_F8)
        static let f9 = Key(rawValue: kVK_F9)
        static let f10 = Key(rawValue: kVK_F10)
        static let f11 = Key(rawValue: kVK_F11)
        static let f12 = Key(rawValue: kVK_F12)
        static let f13 = Key(rawValue: kVK_F13)
        static let f14 = Key(rawValue: kVK_F14)
        static let f15 = Key(rawValue: kVK_F15)
        static let f16 = Key(rawValue: kVK_F16)
        static let f17 = Key(rawValue: kVK_F17)
        static let f18 = Key(rawValue: kVK_F18)
        static let f19 = Key(rawValue: kVK_F19)
        static let f20 = Key(rawValue: kVK_F20)

        // MARK: Navigation

        static let pageUp = Key(rawValue: kVK_PageUp)
        static let pageDown = Key(rawValue: kVK_PageDown)
        static let home = Key(rawValue: kVK_Home)
        static let end = Key(rawValue: kVK_End)
        static let escape = Key(rawValue: kVK_Escape)
        static let help = Key(rawValue: kVK_Help)
        static let leftArrow = Key(rawValue: kVK_LeftArrow)
        static let rightArrow = Key(rawValue: kVK_RightArrow)
        static let downArrow = Key(rawValue: kVK_DownArrow)
        static let upArrow = Key(rawValue: kVK_UpArrow)

        // MARK: Media

        static let volumeUp = Key(rawValue: kVK_VolumeUp)
        static let volumeDown = Key(rawValue: kVK_VolumeDown)
        static let mute = Key(rawValue: kVK_Mute)
    }
}

// MARK: Custom String Mapping
extension Hotkey.Key {
    /// A dictionary that maps arbitrary keys to custom string representations,
    /// giving them priority over their canonical system representations.
    ///
    /// If a key has a corresponding string in the dictionary, it is preferred
    /// over its ``keyEquivalent`` when computing its ``stringValue`` property.
    ///
    /// For example, the key equivalent for the ``space`` key returns a string
    /// consisting solely of the unicode code point U+0020 (" "). While this is
    /// the correct value to use as a key equivalent in a user interface element
    /// (such as a menu item), attempting to display the same value elsewhere can
    /// produce less than satisfactory, often confusing results.
    ///
    /// The space key's custom string mapping spells out the word "Space", which
    /// is how macOS represents the key in its user interface.
    static let customStringMapping: [Self: String] = {
        // standard mappings; nothing special here
        let standardKeys: [Self: String] = [
            .space: "Space",
            .tab: "⇥",
            .return: "⏎",
            .delete: "⌫",
            .forwardDelete: "⌦",
            .f1: "F1",
            .f2: "F2",
            .f3: "F3",
            .f4: "F4",
            .f5: "F5",
            .f6: "F6",
            .f7: "F7",
            .f8: "F8",
            .f9: "F9",
            .f10: "F10",
            .f11: "F11",
            .f12: "F12",
            .f13: "F13",
            .f14: "F14",
            .f15: "F15",
            .f16: "F16",
            .f17: "F17",
            .f18: "F18",
            .f19: "F19",
            .f20: "F20",
            .pageUp: "⇞",
            .pageDown: "⇟",
            .home: "↖",
            .end: "↘",
            .escape: "⎋",
            .leftArrow: "←",
            .rightArrow: "→",
            .downArrow: "↓",
            .upArrow: "↑",
            .capsLock: "⇪",
            .control: "⌃",
            .option: "⌥",
            .shift: "⇧",
            .command: "⌘",
            .rightControl: "⌃",
            .rightOption: "⌥",
            .rightShift: "⇧",
            .rightCommand: "⌘",
            .keypadClear: "⌧",
            .keypadEnter: "⌤",
        ]
        // media key mappings using unicode code points
        let mediaKeys: [Self: String] = [
            .volumeUp: "\u{1F50A}",   // U+1F50A 'SPEAKER WITH THREE SOUND WAVES'
            .volumeDown: "\u{1F509}", // U+1F509 'SPEAKER WITH ONE SOUND WAVE'
            .mute: "\u{1F507}",       // U+1F507 'SPEAKER WITH CANCELLATION STROKE'
        ]
        // keypad key mappings whose strings are enclosed with
        // U+20E3 'COMBINING ENCLOSING KEYCAP'
        let enclosedKeypadKeys: [Self: String] = [
            .keypad0: "0\u{20E3}",
            .keypad1: "1\u{20E3}",
            .keypad2: "2\u{20E3}",
            .keypad3: "3\u{20E3}",
            .keypad4: "4\u{20E3}",
            .keypad5: "5\u{20E3}",
            .keypad6: "6\u{20E3}",
            .keypad7: "7\u{20E3}",
            .keypad8: "8\u{20E3}",
            .keypad9: "9\u{20E3}",
            .keypadDecimal: ".\u{20E3}",
            .keypadDivide: "/\u{20E3}",
            .keypadEquals: "=\u{20E3}",
            .keypadMinus: "-\u{20E3}",
            .keypadMultiply: "*\u{20E3}",
            .keypadPlus: "+\u{20E3}",
        ]
        // other key mappings that include unicode code points
        let unicodeKeys: [Self: String] = [
            .function: "\u{1F310}\u{FE0E}", // U+1F310 'GLOBE WITH MERIDIANS'
            .help: "?\u{20DD}",             // U+20DD  'COMBINING ENCLOSING CIRCLE'
        ]
        return standardKeys
            .merging(mediaKeys, uniquingKeysWith: { $1 })
            .merging(enclosedKeypadKeys, uniquingKeysWith: { $1 })
            .merging(unicodeKeys, uniquingKeysWith: { $1 })
    }()
}

// MARK: Key Equivalent
extension Hotkey.Key {
    /// The system representation of the key.
    ///
    /// You can use this property to set the key equivalent of a menu item or
    /// other user interface element. Note that some keys may not have a valid
    /// system representation, in which case an empty string is returned.
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

// MARK: String Value
extension Hotkey.Key {
    /// A string representation for the key, preferring values from the
    /// ``customStringMapping`` dictionary.
    ///
    /// If the ``customStringMapping`` dictionary does not contain a matching
    /// string for this key, this property checks the system for a valid
    /// representation. If no valid representation can be found, this property
    /// returns an empty string.
    var stringValue: String {
        Self.customStringMapping[self, default: keyEquivalent]
    }
}
