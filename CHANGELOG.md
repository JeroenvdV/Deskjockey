# Changelog

All notable changes to Deskjockey are documented in this file.

## Unreleased

### Bug fixes

- **Fixed restoring scaled resolutions.** Restores failed with "No matching display mode" for HiDPI modes (e.g. "looks like 3008x1692" on a 6K monitor), and the position was dropped with it. Deskjockey now lists HiDPI modes and matches on both points and pixels. If no mode matches, it still restores the position.
- **Changing a resolution keeps the arrangement.** macOS moves a display when its resolution changes, and Deskjockey used to save that new spot. It now moves the display back next to the same neighbor. It also remembers the arrangement for each combination of resolutions, so switching back restores it exactly.

## 1.2.0 - 2026-05-22

### Bug fixes

- **Fixed built-in display matching across macOS name variants.** macOS reports the laptop screen as "Built-in Display" or "Built-in Retina Display" depending on context. Profiles saved under one name now match the other. Existing profiles are migrated automatically on first launch. (Closes #1)
- Fixed `lastUsedAt` being wiped when re-capturing a profile after apply
- Fixed app icon not appearing (was missing from Info.plist due to build config issue)
- Fixed Info.plist using hardcoded version instead of build variables

### New features

- **Application icon** -- Deskjockey now has a custom app icon visible in Finder and Activity Monitor
- **Copy Similar Setup** -- when connecting to monitors with the same native resolutions as a previously saved setup (but different model names), you can copy that configuration
- **Open Config File** -- open the JSON profiles file directly from the menu bar

### Architecture

- Replaced position-based slot assignment with serial/port-based `SlotResolver` -- monitors are now identified by serial number first, then port, then alphabetically. Position is never used as input for matching
- Extracted `SlotResolver` from `Models.swift` into its own file
- Deduplicated test mocks into shared `TestHelpers.swift`
- Removed `FileWatcher` and config file reload feature (non-core, had false-positive issues)
- Test suite refined to 32 focused behavior-level tests

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
