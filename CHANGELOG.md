# Changelog

All notable changes to Deskjockey are documented in this file.

## 2.0.0 - 2026-10-15

- Enumerate display modes with the duplicate-low-resolution option so scaled (HiDPI) saved resolutions restore.
- Standardize domain names across types, commands, files, tests, documentation, and diagnostic fields. Keep version-two storage keys and `profiles.json` compatible.
- Rename the manual commands to **Save Current Configuration** and **Apply Saved Configuration**.
- Remove the **Copy Similar Setup** / **Copy Compatible Configuration** command. Swap identical displays covers the same correction without duplicating class configurations.
- Emit `instance_saved` only after the database save succeeds; use `instance_identified` for identity evidence before persistence.
- Identify display set classes by vendor/product IDs, independent of display names. Keep physical instances separate through model-and-serial identities.
- Store one shared screen configuration per class, with explicit main-slot selection and both logical and pixel mode dimensions.
- Restore exact instance assignments before weaker hints. New instances always receive a complete compatible assignment; absent serials permit session-only assignments.
- Capture new classes both at launch and after connection. System Settings edits update the class; pure permutations update only the instance.
- Apply complete configurations in one validated CoreGraphics transaction. Verify the result before recording a successful restore.
- Added **Swap Identical Displays** for compatible identical-model pairs, including different target modes and displays without usable serials.
- Preserve version-one profiles and an exact backup during conversion to version-two storage. Reject corrupt data, unsupported schemas, and detected external edits without overwriting them.
- Add correlated diagnostic records with input identities, reason codes, assignment decisions, and outcomes. Display failures no longer produce error dialogs.
- Serialize display operations and invalidate session-only assignments on connection events, including reused runtime IDs.

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
