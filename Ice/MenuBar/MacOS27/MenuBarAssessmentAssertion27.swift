//
//  MenuBarAssessmentAssertion27.swift
//  Ice
//
//  Adapted from Barometer's MenuBarAssessmentAssertion.swift
//  (https://github.com/mackid1993/Barometer), itself adapted from Thaw's
//  PlatformRuntimeKit (https://github.com/thaw-app/Thaw). Both are licensed
//  under the GNU GPLv3, like Ice.
//

import Foundation

/// Hides applications' menu bar items through MenuBarAgent's assessment mode.
///
/// A configuration lists the numbered system items and the bundle identifiers
/// that stay on the bar. While the assertion is live, the bar removes every other
/// application's items. Only a signed application bundle can hold one (measured
/// on macOS 27.0: from a command line tool the call succeeds and hides nothing).
@available(macOS 27.0, *)
@MainActor
final class MenuBarAssessmentAssertion27: ConcealmentBackend27 {
    enum Failure: Error, CustomStringConvertible {
        case unavailable
        case rejected(String)
        case timedOut

        var description: String {
            switch self {
            case .unavailable: "MenuBarClientCore is unavailable"
            case .rejected(let reason): "MenuBarAgent rejected the assertion: \(reason)"
            case .timedOut: "MenuBarAgent did not answer within 3 seconds"
            }
        }
    }

    private final class Token: ConcealmentToken27 {
        let assertion: AnyObject

        init(assertion: AnyObject) {
            self.assertion = assertion
        }
    }

    /// Guards a continuation shared by a completion handler and a timeout.
    private final class OneShot: @unchecked Sendable {
        private let lock = NSLock()
        private var claimed = false

        func claim() -> Bool {
            lock.withLock {
                defer { claimed = true }
                return !claimed
            }
        }
    }

    private static let frameworkPath = "/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore"
    private static let configureSelector = NSSelectorFromString("initWithAllowedSystemItems:allowedBundleIdentifiers:")
    private static let activateSelector = NSSelectorFromString("activateWithConfiguration:completionHandler:")
    private static let invalidateSelector = NSSelectorFromString("invalidate")

    /// MenuBarAgent numbers its system items 0 through 8 on macOS 27.0. Ice keeps all of them,
    /// and allows numbers well past 8 so that items a later macOS adds are not hidden: numbers
    /// with no item behind them are ignored (measured on macOS 27.0 with 0 through 63).
    private static let systemItems = (0...63).map { NSNumber(value: $0) } as NSArray

    private static let classes: (configuration: AnyClass, assertion: AnyClass)? = {
        guard
            dlopen(frameworkPath, RTLD_NOW) != nil,
            let configuration = NSClassFromString("MBAssessmentModeConfiguration"),
            let assertion = NSClassFromString("MBAssessmentModeAssertion"),
            configuration.instancesRespond(to: configureSelector),
            assertion.instancesRespond(to: activateSelector),
            assertion.instancesRespond(to: invalidateSelector)
        else {
            return nil
        }
        return (configuration, assertion)
    }()

    /// Whether this macOS build offers the assertion.
    static var isAvailable: Bool {
        classes != nil
    }

    func activate(allowedBundleIDs: [String]) async throws -> ConcealmentToken27 {
        guard
            let classes = Self.classes,
            let configuration = (classes.configuration.alloc() as AnyObject)
                .perform(Self.configureSelector, with: Self.systemItems, with: allowedBundleIDs as NSArray)?
                .takeUnretainedValue(),
            let assertion = (classes.assertion.alloc() as AnyObject)
                .perform(NSSelectorFromString("init"))?
                .takeUnretainedValue()
        else {
            throw Failure.unavailable
        }
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let oneShot = OneShot()
                let completion: @convention(block) (Any?) -> Void = { error in
                    guard oneShot.claim() else {
                        return
                    }
                    if let error {
                        continuation.resume(throwing: Failure.rejected(String(describing: error)))
                    } else {
                        continuation.resume()
                    }
                }
                _ = assertion.perform(Self.activateSelector, with: configuration, with: completion)
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    guard oneShot.claim() else {
                        return
                    }
                    continuation.resume(throwing: Failure.timedOut)
                }
            }
        } catch {
            _ = assertion.perform(Self.invalidateSelector)
            throw error
        }
        return Token(assertion: assertion)
    }

    func invalidate(_ token: ConcealmentToken27) {
        guard let token = token as? Token else {
            return
        }
        _ = token.assertion.perform(Self.invalidateSelector)
    }
}
