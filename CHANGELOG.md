# Changelog

All notable changes to Deskjockey are documented in this file.

## Unreleased

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
