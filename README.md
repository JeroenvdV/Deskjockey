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
resolutions, everything. It identifies monitors by model name, not by cable or port, so
swapping a USB-C side or using a different dock just works.

## Features

- **Automatic profile switching** -- detects monitor changes and reapplies your saved layout within seconds.
- **Per-display sync status** -- see at a glance which monitors match your saved profile and which don't.
- **Cable/port agnostic** -- matches monitors by model name, not by runtime ID. Move to a different dock or swap cables freely.
- **Multi-monitor aware** -- handles any number of displays, including duplicate models (e.g. two identical external monitors at different positions).
- **Menu bar native** -- lives in your menu bar with a single icon. No windows, no Dock clutter.
- **Launch at Login** -- set it and forget it.

## How It Works

```
Plug in monitors
       |
       v
Deskjockey detects display change
       |
       v
Builds signature from model names  -->  "Dell U2405x2 + MacBook Pro Displayx1"
       |
       v
Saved profile found?
  Yes --> Apply saved positions & resolutions
  No  --> Capture current setup as new profile
```

Profiles are stored as JSON in `~/Library/Application Support/Deskjockey/profiles.json`.
Logs are in `~/Library/Logs/Deskjockey/deskjockey.log` if you want to see what's happening.

## Menu Bar

```
  ┌──────────────────────────────────────────────┐
  │  Profile: In Sync                            │
  │──────────────────────────────────────────────│
  │  Displays (3)                                │
  │  ✓  MacBook Pro Display (built-in)  1728x1117│
  │  ✓  Dell U2405                      1920x1200│
  │  ✓  Dell U2405                      1920x1200│
  │──────────────────────────────────────────────│
  │  Save Current Setup                     ⌘S   │
  │  Re-apply Saved Setup                   ⌘R   │
  │──────────────────────────────────────────────│
  │  ✓  Launch at Login                          │
  │──────────────────────────────────────────────│
  │  Quit Deskjockey                        ⌘Q   │
  └──────────────────────────────────────────────┘
```

The menu bar icon tints orange when your current setup is out of sync with the saved profile.

## Install

### Download the .app from the Releases page

And then just drag it to Applications, launch it and tell it to launch at login from the menu bar icon.

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

Your saved profiles are preserved across updates.

## Architecture

```
DeskjockeyCore (framework, platform-independent)
├── Models.swift             # DisplaySnapshot, MonitorSetSignature, SlotPlanner, DisplayMatcher
├── DisplayConfigurationCoordinator.swift   # Profile capture, reapply, sync checking
├── ProfileStore.swift       # JSON persistence
├── DisplayManaging.swift    # Protocols + FileLogger
├── Debouncer.swift          # Reusable debounce utility
└── Errors.swift             # Typed error enums

DeskjockeyApp (macOS app target)
├── DeskjockeyAppMain.swift    # App entry point
├── AppDelegate.swift        # Menu bar UI, display change handling
└── Runtime.swift            # CoreGraphics display manager, overlay, login items
```

`DeskjockeyCore` contains all logic and is fully testable with mocks -- no AppKit or CoreGraphics
dependency. `DeskjockeyApp` provides the macOS-specific runtime.

## Known Limitations

- macOS does not expose stable public APIs for every display arrangement operation on all
  hardware. This app uses public CoreGraphics APIs; behavior may vary across macOS versions
  and display hardware.
- Resolution matching requires the target mode to be available in the display's mode list.
  If your monitor doesn't advertise a previously used resolution, that part of the profile
  is skipped.

## Contributing

Pull requests welcome. The test suite runs with `swift test` -- no hardware required, all
display interactions are mocked.

## License

MIT
