# Contributing to Ice

Thanks for your interest in contributing to Ice! This guide covers the minimum you need to get running and get a PR merged.

Please also read [CODE_OF_CONDUCT.md](../CODE_OF_CONDUCT.md). By participating, you agree to follow it.

## Requirements

- macOS 14+ (project relies on macOS 14 system APIs)
- Latest stable Xcode
- SwiftLint: `brew install swiftlint`

## Quick start

```bash
git clone https://github.com/cavaldos/Ice.git
cd Ice

# Build Debug and launch the app
./script/run.sh

# Before pushing — same lint + build as CI
./script/ci-local.sh
```

Other helpers live in [script/README.md](../script/README.md):

- `./script/build.sh [vX.Y.Z]` — Build Release DMG into `release/`
- `./script/release.sh` / `./script/update-appcast.sh` — maintainers only, for releases

## Project layout

- `Ice/` — app source (`MenuBar/`, `Settings/`, `Hotkeys/`, `Updates/`, `UI/`, `Utilities/`, …)
- `Ice.xcodeproj/` — Xcode project (version is injected from the git tag in CI, don't edit by hand)
- `script/` — dev and release helpers
- `Resources/` — demo images/video used by README
- `.github/workflows/` — `lint.yml` (SwiftLint `--strict`), `release.yml`

## Coding conventions

- SwiftLint must pass with `--strict` (`./script/ci-local.sh` runs it).
- 4 spaces, no tabs.
- New Swift files need the header:
  ```swift
  //
  //  <Filename>
  //  Ice
  //
  ```
- Avoid `force_unwrapping` / `implicitly_unwrapped_optional` — both are opt-in lint rules.
- Keep changes scoped: one PR = one fix or feature.

## How to contribute

1. Check existing [issues](https://github.com/cavaldos/Ice/issues) — bug reports and feature requests have templates, please use them.
2. Fork the repo and create a branch: `feat/short-name` or `fix/short-name`.
3. Make your change and verify:
   ```bash
   ./script/ci-local.sh
   ```
4. Commit with a clear message (`feat: …`, `fix: …`, `docs: …`, `chore: …`).
5. Push and open a PR against `main`. Describe what changed, why, and how you tested it (macOS version + screenshots/video for UI changes).

## What to work on

Good first contributions: small bug fixes, UI polish, docs, and reproducible bug reports. Large refactors or new features — open an issue first to agree on scope before coding.

## License

Contributions are licensed under [GPL-3.0](../LICENSE).
