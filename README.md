<div align="center">

# Deskjockey

**Your multi-monitor setup, remembered.**

A macOS utility that automatically saves and restores monitor arrangements
when you move between desks.

[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue)](https://github.com/JeroenvdV/misc)
[![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange)](https://github.com/JeroenvdV/misc)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

</div>

---

## The Problem

You use your MacBook at multiple desks. All of them have the same monitor. Yet when you plug in to a specific desk for the first time, you get the same old defaults, and you've lost the position, resolution and which monitor is main.

You fix it manually in System Settings, Again. And again.

## The Solution

Deskjockey sits in your menu bar and learns your monitor setups. When it recognizes a set of
the same kinds of monitors you've used before, it restores your previous arrangement automatically -- positions,
resolutions, everything. It identifies model classes through vendor/product IDs and physical instances through model-and-serial identities.
Names are labels only; a cable or dock change does not define a new class.

## Features

- **Automatic configuration restore** -- detects monitor changes and reapplies your saved layout within seconds.
- **Visual feedback** -- menu bar icon flashes green when a display change is processed, and the menu shows how long ago the last change was handled.
- **Per-display sync status** -- see at a glance which monitors match your saved configuration and which don't.
- **Cable/port agnostic** -- uses vendor/product IDs and usable serials, not runtime IDs, for persistent identity. Missing serials permit a session-only assignment.
- **Multi-monitor aware** -- handles any number of displays, including duplicate models (e.g. two identical external monitors at different positions).
- **Swap Identical Displays** -- exchange two identical external screens with one menu action, without a separate class configuration.
- **Single app instance** -- launching a second copy signals the running instance to show its menu, then exits.
- **Menu bar native** -- lives in your menu bar with a single icon. No windows, no Dock clutter.
- **Launch at Login** -- set it and forget it.
- **Open Config File** -- open the JSON configuration file directly from the menu bar to edit it manually.

## How It Works

```
Plug in monitors
       |
       v
Deskjockey detects display change
       |
       v
Identifies the model class from vendor/product IDs and counts
       |
       v
Known display set class?
  Yes --> Resolve the instance assignments, then apply the class configuration
  No  --> Capture the current configuration as a new class
```

A class owns shared positions, scaling, resolution, and main-display selection.
An instance owns only the assignment of its physical monitors to those slots.
Changes in System Settings update the class automatically; a pure swap updates only the instance.
New instances receive a complete assignment even when physical left/right order is unknown.

The display set database is stored as JSON in `~/Library/Application Support/Deskjockey/profiles.json`.
Logs are in `~/Library/Logs/Deskjockey/deskjockey.log` if you want to see what's happening.

## Swap Identical Displays

Two identical screens can have an unknown physical order, even when each screen has a distinct serial number.
A hub port or a name suffix such as `(1)` does not mean "left" or "right".

The menu offers **Swap Identical Displays** for a compatible pair of identical external screens.
Click it if the physical left and right screens do not match the saved arrangement.
Click it again to undo the swap.

The swap exchanges monitor assignments and applies the destination slots' full settings in one display transaction.
The shared layout, slot resolutions, and main-slot selection remain unchanged.
Deskjockey recalls the corrected assignment when model-and-serial identities remain usable and stable.
Missing or duplicate serials permit a session-only correction, not a promise of recall after reconnect.

The menu offers compatible pairs, including pairs with different target modes.
Each display must support its destination mode.
Mirror mode is not supported.
Save or apply the current configuration first if the pair differs from its saved configuration.

Vendor/product IDs identify models; names such as `LEN T23i-20 (1)` remain unchanged.
Existing version-one records remain in the version-two database.
The first conversion also creates an exact `profiles.json.v1-backup` beside the configuration file.
Only an unambiguous live correspondence can reuse a legacy configuration.
The app retains conflicting or unresolved legacy data instead of deleting it.

### What the hardware can tell us

Serial numbers can identify monitors, but they do not specify physical desk positions.
`logicalUnitNumber` stores `CGDisplayUnitNumber`, a macOS logical unit number, not a physical hub port.
A USB dock serial can identify a dock, but the public display data used here does not associate screens with that dock.
Neither identity establishes physical left or right without a prior user choice.

Some DisplayLink docks support [preconfigured desk layouts](https://support.displaylink.com/knowledgebase/articles/1905775-dock-management-tool-user-guide).
The documented tool requires Windows and an administrator-defined layout; it does not sense physical positions.
Deskjockey does not depend on this vendor-specific feature.

## Menu Bar

```
  ┌──────────────────────────────────────────────┐
  │  In Sync · last change 5 min. ago            │
  │──────────────────────────────────────────────│
  │  Displays (3)                                │
  │  ✓  MacBook Pro Display (built-in)  1728x1117│
  │  ✓  Dell U2405                      1920x1200│
  │  ✓  Dell U2405                      1920x1200│
  │──────────────────────────────────────────────│
  │  Manual Operations                        ▶  │
  │──────────────────────────────────────────────│
  │  Open Config File                            │
  │──────────────────────────────────────────────│
  │  ✓  Launch at Login                          │
  │──────────────────────────────────────────────│
  │  Quit Deskjockey v2.0.0                 ⌘Q   │
  └──────────────────────────────────────────────┘
```

The menu bar icon flashes green when a display change is processed, and tints orange when the current displays are out of sync with the saved configuration.

## Install

### Homebrew (recommended)

```bash
brew tap JeroenvdV/deskjockey
brew install --cask deskjockey
```

### Download from GitHub Releases

Download `Deskjockey.zip` from the [Releases page](https://github.com/JeroenvdV/Deskjockey/releases), unzip, move to `/Applications`, then run:

```bash
xattr -cr /Applications/Deskjockey.app
```

This is needed because the app is not signed with an Apple Developer ID. Then launch it and click the menu bar icon to enable "Launch at Login".

### Build from source

Requires Xcode 15+ and macOS 13+.

```bash
git clone git@github.com:JeroenvdV/Deskjockey.git
cd Deskjockey

# Generate Xcode project and build
xcodegen generate
xcodebuild -project Deskjockey.xcodeproj -scheme Deskjockey -configuration Release build

# Install
cp -R ~/Library/Developer/Xcode/DerivedData/Deskjockey-*/Build/Products/Release/Deskjockey.app /Applications/

# Launch
killall Deskjockey
open /Applications/Deskjockey.app
```

See the monitor icon in the menu bar. Click it for the menu and click 'Launch at Login' to enable that.

### Update

```bash
killall Deskjockey 2>/dev/null
# Repeat build steps above, then relaunch
open /Applications/Deskjockey.app
```

Your saved configurations and instance assignments are preserved across updates.

## Architecture

```
DeskjockeyCore (framework, platform-independent)
├── DisplaySetModels.swift             # Typed classes, instances, slots, and configurations
├── ScreenConfigurationLogic.swift # Validation, capture, permutations, and complete plans
├── SlotAssignmentResolver.swift       # Exact-instance and complete fallback assignments
├── LegacyProfileMigration.swift # Conservative version-one conversion
├── DetectionLog.swift       # Correlated diagnostic records
├── DisplaySetPresentation.swift # Menu state and explicit configuration copy
├── ScreenConfigurationCoordinator.swift   # Configuration capture, restore, and sync status
├── DisplaySetStore.swift       # JSON persistence
├── DisplayManaging.swift    # Protocols + FileLogger
├── Debouncer.swift          # Reusable debounce utility
└── DisplaySetError.swift             # Typed error enums

DeskjockeyApp (macOS app target)
├── DeskjockeyAppMain.swift  # App entry point, single-instance lock
├── AppDelegate.swift        # Menu bar UI, display change handling
└── Runtime.swift            # CoreGraphics display manager, login items
```

`DeskjockeyCore` contains all logic and is fully testable with mocks -- no AppKit or CoreGraphics
dependency. `DeskjockeyApp` provides the macOS-specific runtime.

## Known Limitations

- macOS does not expose stable public APIs for every display arrangement operation on all
  hardware. This app uses public CoreGraphics APIs; behavior may vary across macOS versions
  and display hardware.
- Resolution matching requires the target mode to be available in the display's mode list.
  If a display does not support its target logical and pixel dimensions, the complete apply operation is skipped.
- Unknown model IDs, mirror mode, or unsupported geometry can prevent automatic changes.
- Driver-reported identities can change. Stable serials are necessary for reliable instance recognition.
- External changes on an unchanged display set remain authoritative, including automatic macOS adjustments.

Failures appear in the diagnostic log, not error dialogs. Detection records include IDs, reasons, assignments, and outcomes.
See [Intended behavior](BEHAVIOR.md) for the definitions and detailed operating rules.

## Contributing

Pull requests welcome. The test suite runs with `swift test` -- no hardware required, all
display interactions are mocked.

## License

MIT
