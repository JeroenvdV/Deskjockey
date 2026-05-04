# Deskjockey — Agent Instructions

## What this project is

macOS menu bar utility that saves and restores multi-monitor display arrangements.
Swift 5.9, macOS 13+, no external dependencies.

## Key files

- `DEVELOPMENT.md` — build, test, architecture, persistence, release process, and Homebrew tap setup. Read this before making changes.
- `CHANGELOG.md` — all notable changes by version.
- `README.md` — user-facing manual file that should be kept up-to-date with any changes.
- `project.yml` — XcodeGen spec. Source of truth for version number (`MARKETING_VERSION`), build number, bundle ID, and build settings.
- `Package.swift` — SPM manifest. Used for `swift test` only; does not embed version info.

## Rules

- Do not modify files in DeskjockeyCore without running `swift test` afterward.
- The XcodeGen project (`project.yml`) is the source of truth for the Xcode build, not `Package.swift`.
- When changing the version number, update both `project.yml` and `CHANGELOG.md`. See DEVELOPMENT.md for the full list of places.
- The Homebrew tap is a separate repo (`homebrew-deskjockey`). See DEVELOPMENT.md section "Cutting a release" for the update workflow.
