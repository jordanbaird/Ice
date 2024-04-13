//
//  ScreenState.swift
//  Ice
//

/// A type that represents the state of a screen.
enum ScreenState {
    /// The screen is locked.
    case locked
    /// The screen is unlocked.
    case unlocked
    /// The screen saver is active.
    case screenSaver
}

extension ScreenState {
    /// The current screen state.
    static var current: ScreenState {
        if ScreenStateManager.shared.screenSaverIsActive {
            return .screenSaver
        }
        if ScreenStateManager.shared.screenIsLocked {
            return .locked
        }
        return .unlocked
    }
}
