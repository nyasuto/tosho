# Repository Guidelines

## Project Structure & Module Organization
The macOS app follows an MVVM layout. Entry points live in `App/` (application delegate, commands) and `Managers/` & `Sessions/` coordinate multi-window reading sessions. UI is split across `Views/`, with state in `ViewModels/ReaderViewModel.swift`. Domain logic and persistence helpers are in `Models/`, while archive handling and file history live in `Services/`. Shared diagnostics sit in `Utilities/DebugLogger.swift`, assets in `Resources/`, and any future tests belong under `Tests/`.

## Build, Test, and Development Commands
Use the Makefile targets:
- `make setup-dev` installs SwiftLint on new machines.
- `make build` uses Xcode (`DEVELOPER_DIR` aware) to compile the Debug build to `build/Build/Products/Debug/`.
- `make test` runs the project’s unit tests via `xcodebuild test`.
- `make quality` chains linting and the Debug build; CI calls this before building.
- `make run` launches the compiled app bundle. For release work, use `make build-release` or `make archive`.

## Coding Style & Naming Conventions
Swift source uses four-space indentation and an 120-character soft limit enforced through `.swiftlint.yml`. Name types in `UpperCamelCase`, properties and methods in `lowerCamelCase`, and align filenames with their primary type (e.g., `ReadingSessionManager.swift`). SwiftLint (`make lint`/`make format`) enforces modifier order, unused imports, and other opt-in rules; run it before committing.

## Testing Guidelines
Unit and integration tests should target the `Tosho` scheme with XCTest. Name classes `<Feature>Tests` and methods `test_<behavior>`. Execute locally with `make test` (or `xcodebuild test -scheme Tosho`). Place fixtures under `Resources/Sample*` and clean them up to keep the bundle lean. Aim to cover archive extraction edge cases, multi-window session teardown, and reader navigation logic.

## Commit & Pull Request Guidelines
Follow the existing short, behavior-focused subject lines (`fix: …`, `feat: …`, `refactor: …`). Reference issues using `(#NN)` or `Closes #NN` in the body. Before opening a PR, run `make quality`, `make build`, and `make test`. PR descriptions should summarize the change, list validation steps, and attach screenshots or screen recordings for UI-visible updates. Link relevant issues and call out follow-ups or known gaps.

## Architecture & Configuration Notes
Multi-window management is centralized in `Managers/ReadingSessionManager.swift` and `Sessions/ReadingSession.swift`; always route new reader windows through this layer to ensure security-scoped bookmarks and background tasks are cleaned up. CI runs on macOS 14 using the full Xcode toolchain—if you add scripts, keep them compatible with non-interactive runners and respect the `DEVELOPER_DIR` environment variable.

## Communication
- ユーザーへの応答・PR・Issue・レビューコメントなど、公開コミュニケーションは原則として日本語で記述してください。
