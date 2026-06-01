# Repository Guidelines

## Project Structure & Module Organization
`MacAppClean` is a Swift Package executable for macOS 14+.

- `Sources/MacAppClean/App`: app entry (`MacAppCleanApp.swift`)
- `Sources/MacAppClean/Views`: SwiftUI screens (sidebar, inspector, settings, lists)
- `Sources/MacAppClean/Stores`: state and app workflow logic
- `Sources/MacAppClean/KnowledgeBase`: rule models, provider, resolver, update checks
- `Sources/MacAppClean/Models` and `Support`: shared domain models and helpers
- `Sources/MacAppClean/Resources`: static assets (icons, bundled files)
- `Tests/MacAppCleanTests`: unit tests for resolver/provider logic
- `script/`: build/run/verification scripts
- `docs/`: research and design notes

Keep new code in the closest existing module instead of adding new top-level folders.

## Build, Test, and Development Commands
- `swift build`: compile the app target.
- `swift test`: run unit tests.
- `./script/build_and_run.sh`: build and launch app.
- `./script/build_and_run.sh --verify`: smoke launch check only.
- `./script/build_and_run.sh --debug`: debug build/run path.
- `./script/verify_app.sh`: full local gate (`build + test + verify`).
- `./script/verify_scan.sh`: quick shell-based scan sanity check.

Run `./script/verify_app.sh` before opening a PR.

## Coding Style & Naming Conventions
Use idiomatic Swift 5.9 style:
- 4-space indentation, no tabs.
- Types/protocols: `UpperCamelCase`; vars/functions: `lowerCamelCase`.
- File names should match the primary type (`RelatedFileResolver.swift`).
- Prefer small, focused extensions over large utility files.

No formatter/linter is enforced in this repo today; keep style consistent with nearby files.

## Testing Guidelines
Tests use `XCTest` via SwiftPM (`MacAppCleanTests` target).  
Name tests as `test_<behavior>_<expectedResult>()` (or equivalent readable pattern).  
Add/adjust tests for any changes in resolver logic, knowledge base parsing, or risk/default-selection behavior.

## Commit & Pull Request Guidelines
Recent history mixes imperative subjects and Conventional Commit prefixes. Prefer:
- `feat: ...`, `fix: ...`, `docs: ...`, `test: ...`, `refactor: ...`

Keep commit messages concise and scoped.  
PRs should include:
- what changed and why,
- validation steps/results (e.g., `swift test`, `./script/verify_app.sh`),
- screenshots for UI-visible changes,
- linked issue/task when available.

## Security & Safety Notes
This app handles deletion workflows. Preserve the “move to Trash” behavior (`trashItem`) and avoid introducing permanent-delete paths unless explicitly required and reviewed.
