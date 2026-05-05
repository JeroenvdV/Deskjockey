# Changelog

All notable changes to Deskjockey are documented in this file.

## Unreleased

- Added comprehensive test coverage: 52 tests covering core functionality (was 18)
- Test coverage improved: 88.7% function coverage, 93.4% line coverage (was 67.4%, 83.3%)
- Added tests for ProfileStore, Debouncer, FileLogger, and error handling in Coordinator
- Refactored duplicate display sorting logic into reusable `sortedByPosition()` extensions
- Fixed FileWatcher to monitor specific file instead of parent directory
- Added comprehensive coding guidelines and architecture documentation to DEVELOPMENT.md

## 1.1.0 - 2026-05-04

- Menu bar icon briefly flashes green when a display change is processed
- New menu item showing how long ago the last display change was processed (e.g. "Processed changes 2 minutes ago"), persisted across launches
- Removed dark overlay that flashed the screen during display reconfiguration
- Single-instance enforcement: launching a second instance now signals the running one to show its menu, then exits
- Added Homebrew tap for installation (`brew tap JeroenvdV/deskjockey`)
- Updated README with Homebrew, manual download, and build-from-source install instructions

## 1.0.0 - 2026-04-24

First stable release.

- Automatic profile switching when monitors are plugged/unplugged
- Per-display sync status in menu bar
- Cable/port-agnostic monitor matching by model name
- Multi-monitor support including duplicate models
- Menu bar UI with save, re-apply, and launch-at-login
- Version shown in menu bar dropdown
- Profile storage in `~/Library/Application Support/Deskjockey/profiles.json`
- Logging to `~/Library/Logs/Deskjockey/deskjockey.log`

## 0.0.0 - 2026-04-24

Initial development release.
