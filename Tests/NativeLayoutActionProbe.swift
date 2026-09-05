// Narrow installed-Ice Layout QA, not part of the application target.
// swiftc -parse-as-library Tests/NativeLayoutActionProbe.swift -o <probe>
// Read-only inventory: <probe>
// Optional explicit action (never used by the preparation agent):
// <probe> <App 音量|Macs Fan Control|Spotlight> \
//   <Move Left|Move Right|Move to Hidden|Move to Visible> [count: 1...3]
//
// Only a currently on-screen window of the exact /Applications/Ice.app is
// inspected. Menu extras, app menus, notification contents, global events and
// coordinates are never used. Each invocation selects a unique advertised
// raw action whose AXUIElementCopyActionDescription matches the literal action
// request, and passes that exact raw name back unchanged. No raw action name is
// constructed or guessed. AXCustomActions metadata is printed but never
// converted to a proxy. If actions are unavailable, use native Layout UI QA.
// Existing accessibility trust is checked without requesting any permission.

import AppKit
import ApplicationServices

private enum ProbeError: Error {
    case invalidArguments, permissionUnavailable, applicationUnavailable
    case windowUnavailable, itemUnavailable, actionUnavailable, actionFailed(Int32)
}

private func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
    return value as? T
}

private func frame(_ element: AXUIElement) -> CGRect? {
    guard let position: AXValue = attribute(element, kAXPositionAttribute),
          let size: AXValue = attribute(element, kAXSizeAttribute) else { return nil }
    var point = CGPoint.zero
    var dimensions = CGSize.zero
    guard AXValueGetValue(position, .cgPoint, &point), AXValueGetValue(size, .cgSize, &dimensions),
          [point.x, point.y, dimensions.width, dimensions.height].allSatisfy(\.isFinite),
          dimensions.width > 0, dimensions.height > 0 else { return nil }
    return CGRect(origin: point, size: dimensions)
}

private func actions(_ element: AXUIElement) -> [String] {
    var names: CFArray?
    guard AXUIElementCopyActionNames(element, &names) == .success else { return [] }
    return names as? [String] ?? []
}

private func actionDescription(_ element: AXUIElement, name: String) -> String? {
    var description: CFString?
    guard AXUIElementCopyActionDescription(element, name as CFString, &description) == .success else { return nil }
    return description as String?
}

@main
private struct NativeLayoutActionProbe {
    private static let allowedSources = ["App 音量", "Macs Fan Control", "Spotlight"]
    private static let allowedActions = ["Move Left", "Move Right", "Move to Hidden", "Move to Visible"]

    @MainActor
    static func main() {
        do {
            guard AXIsProcessTrusted() else { throw ProbeError.permissionUnavailable }
            let args = Array(CommandLine.arguments.dropFirst())
            let count: Int
            if args.isEmpty {
                count = 0
            } else if (2...3).contains(args.count), allowedSources.contains(args[0]), allowedActions.contains(args[1]),
                      let requested = args.count == 3 ? Int(args[2]) : 1, (1...3).contains(requested) {
                count = requested
            } else { throw ProbeError.invalidArguments }
            let app = try installedIce()
            let pid = app.processIdentifier
            if count == 0 {
                let items = try layoutItems(pid: pid)
                print("Ice PID=\(pid), path=/Applications/Ice.app, layoutItems=\(items.count)")
                for item in items { describe(item) }
                return
            }
            for index in 1...count {
                guard try installedIce().processIdentifier == pid else { throw ProbeError.applicationUnavailable }
                // Refresh before every action; never retain a rebuilt Layout
                // element as the next source after a physical move completes.
                let current = try layoutItems(pid: pid).filter { label($0) == args[0] }
                guard current.count == 1, let item = current.first,
                      (attribute(item, kAXEnabledAttribute) as Bool?) != false else { throw ProbeError.itemUnavailable }
                let matchingActions = actions(item).filter { actionDescription(item, name: $0) == args[1] }
                guard matchingActions.count == 1, let rawAction = matchingActions.first else { throw ProbeError.actionUnavailable }
                let started = ProcessInfo.processInfo.systemUptime
                let result = AXUIElementPerformAction(item, rawAction as CFString)
                print("Action \(index)/\(count): \(args[0]) / \(args[1]), AX=\(result.rawValue), ackMs=\((ProcessInfo.processInfo.systemUptime - started) * 1000)")
                guard result == .success else { throw ProbeError.actionFailed(result.rawValue) }
            }
            print("AX acknowledgements only; verify physical order and Layout after convergence separately.")
        } catch {
            FileHandle.standardError.write(Data("Layout probe stopped: \(error). No unsupported action fallback was attempted.\n".utf8))
            exit(1)
        }
    }

    @MainActor
    private static func installedIce() throws -> NSRunningApplication {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.jordanbaird.Ice")
        guard apps.count == 1, let app = apps.first, !app.isTerminated,
              app.bundleURL?.standardizedFileURL.path == "/Applications/Ice.app" else { throw ProbeError.applicationUnavailable }
        return app
    }

    private static func label(_ element: AXUIElement) -> String {
        (attribute(element, kAXDescriptionAttribute) as String?) ?? (attribute(element, kAXTitleAttribute) as String?) ?? ""
    }

    private static func layoutItems(pid: pid_t) throws -> [AXUIElement] {
        let root = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(root, 0.3)
        let windows: [AXUIElement] = attribute(root, kAXWindowsAttribute) ?? []
        let nativeWindows = (CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? [])
            .filter { ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid }
        let visibleWindows = windows.filter { window in
            guard let bounds = frame(window), (attribute(window, kAXMinimizedAttribute) as Bool?) != true else { return false }
            return nativeWindows.contains { native in
                guard let dictionary = native[kCGWindowBounds as String] as? [String: Any],
                      let nativeBounds = CGRect(dictionaryRepresentation: dictionary as CFDictionary) else { return false }
                return abs(nativeBounds.minX - bounds.minX) < 1 && abs(nativeBounds.minY - bounds.minY) < 1 &&
                    abs(nativeBounds.width - bounds.width) < 1 && abs(nativeBounds.height - bounds.height) < 1
            }
        }
        guard !visibleWindows.isEmpty else { throw ProbeError.windowUnavailable }
        var queue = visibleWindows.map { ($0, 0) }
        var visited = 0
        var result = [AXUIElement]()
        while !queue.isEmpty, visited < 512 {
            let (element, depth) = queue.removeFirst()
            visited += 1
            if (attribute(element, kAXHelpAttribute) as String?) == "Drag to reorder this menu bar item", frame(element) != nil {
                result.append(element)
                continue
            }
            guard depth < 16 else { continue }
            let children: [AXUIElement] = attribute(element, kAXChildrenAttribute) ?? []
            queue.append(contentsOf: children.map { ($0, depth + 1) })
        }
        guard !result.isEmpty else { throw ProbeError.itemUnavailable }
        return result
    }

    private static func describe(_ element: AXUIElement) {
        var names: CFArray?
        AXUIElementCopyAttributeNames(element, &names)
        let attributeNames = names as? [String] ?? []
        let customNames = attributeNames.filter { $0.localizedCaseInsensitiveContains("custom") }
        print("Item: \(label(element)); role=\((attribute(element, kAXRoleAttribute) as String?) ?? "unknown"); frame=\(String(describing: frame(element)))")
        for name in actions(element) {
            print("  action=\(name), description=\(actionDescription(element, name: name) ?? "")")
        }
        for name in customNames {
            let value: AnyObject? = attribute(element, name)
            print("  metadata \(name)=\(String(describing: value))")
        }
        if customNames.isEmpty { print("  No custom-action attribute is advertised.") }
    }
}
