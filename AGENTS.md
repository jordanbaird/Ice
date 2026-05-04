# AGENTS.md

## Project Overview

Ice is a macOS menu bar management tool built with Swift/SwiftUI. Requires macOS 14+. Single Xcode project (no SPM, no multi-target). Not sandboxed.

## Developer Commands

- **Build**: Open `Ice.xcodeproj` in Xcode and run (⌘R)
- **Lint**: `swiftlint --strict` (CI runs this on ubuntu via `norio-nomura/action-swiftlint`)
- **No test suite**: No test targets exist in the project
- **No pre-commit hooks**

## Architecture

- **Entry point**: `Ice/Main/IceApp.swift` (`@main` SwiftUI App)
- **Central state**: `Ice/Main/AppState.swift` — single source of truth, passed to all views/managers
- **Lifecycle**: `Ice/Main/AppDelegate.swift` (NSApplicationDelegate, assigned via `@NSApplicationAdaptor`)
- **Startup flow**: `IceApp.init()` → `MigrationManager.migrateAll()` → `AppDelegate.performSetup()` (after permission check)

### Key Directories

| Directory | Purpose |
|---|---|
| `MenuBar/` | Core hiding/showing logic, layout, search, appearance, spacing |
| `Settings/` | Settings panes and settings manager hierarchy |
| `Bridging/` | Private CGS* API wrappers (window server connection, spaces, process responsivity) |
| `Bridging/Shims/` | `Private.swift` (private C function declarations), `Deprecated.swift` |
| `Hotkeys/` | Keyboard shortcut management |
| `Permissions/` | Permission checking (accessibility, screen recording, etc.) |
| `Swizzling/` | Runtime method swizzling (NSSplitViewItem) |
| `Updates/` | Sparkle framework auto-updates |
| `Utilities/` | Shared types: Logger, Defaults, Extensions, MigrationManager |

## Important Context

- **Private APIs**: `Bridging/` uses private CGS* functions (CGSSetConnectionProperty, CGSGetWindowList, etc.). These are declared in `Bridging/Shims/Private.swift`. Changes to window/menu bar manipulation likely touch this layer.
- **Not sandboxed**: `Ice.entitlements` has `com.apple.security.app-sandbox = false`. This is required for private API access.
- **Logger**: Custom `Logger` wrapper around `os.Logger` with subsystem `com.jordanbaird.Ice`. Use `Logger(category:)` with a static per-file extension (see any file for pattern).
- **Defaults**: UserDefaults-based persistence via `Defaults.swift`. New settings need a `DefaultsKey` entry.
- **Migration**: `MigrationManager` handles version-to-version data migrations. New breaking changes need a migration step.

## SwiftLint Config

- Many strictness rules disabled (complexity, file/function length, naming, tuple size)
- Opt-in rules enabled: multiline argument/parameter formatting, modifier order (acl first), trailing commas, indentation width, closure spacing
- Custom rule: `@objc dynamic` ordering, no tabs (4-space indent required)
- File header required: `// Ice //` comment block

## CI

Single workflow (`.github/workflows/lint.yml`): SwiftLint `--strict` on push/PR to `main` for `*.swift` changes.

## Notes

- Active development — many roadmap features not yet implemented (see README)
- Homebrew cask: `brew install --cask jordanbaird-ice`
- Uses Sparkle for updates (feed: `jordanbaird.github.io/ice-releases/appcast.xml`)
