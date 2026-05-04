# Development Guide

## Prerequisites

- macOS 13+ (Ventura)
- Xcode 15+ (Swift 5.9)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

## Build

Two build systems are available. XcodeGen + xcodebuild produces the `.app` bundle with correct
Info.plist (version, bundle ID, LSUIElement). SPM is used for tests only.

```bash
# Generate Xcode project from project.yml
xcodegen generate

# Debug build
xcodebuild -project Deskjockey.xcodeproj -scheme Deskjockey -configuration Debug build

# Release build
xcodebuild -project Deskjockey.xcodeproj -scheme Deskjockey -configuration Release build

# The built app is at (the hash suffix varies per machine):
BUILD_DIR=$(xcodebuild -project Deskjockey.xcodeproj -scheme Deskjockey -configuration Release -showBuildSettings 2>/dev/null | grep ' BUILD_DIR' | awk '{print $3}')
# e.g. $BUILD_DIR/Release/Deskjockey.app
```

## Test

```bash
swift test
```

All display interactions are mocked via the `DisplayManaging` protocol in DeskjockeyCore.
No hardware required.

## Install locally

```bash
pkill -x Deskjockey 2>/dev/null
xcodegen generate
xcodebuild -project Deskjockey.xcodeproj -scheme Deskjockey -configuration Release build
BUILD_DIR=$(xcodebuild -project Deskjockey.xcodeproj -scheme Deskjockey -configuration Release -showBuildSettings 2>/dev/null | grep ' BUILD_DIR' | awk '{print $3}')
cp -R "$BUILD_DIR/Release/Deskjockey.app" /Applications/
open /Applications/Deskjockey.app
```

## Architecture

```
DeskjockeyCore (framework, platform-independent)
├── Models.swift                          # Geometry, snapshots, signatures, matching
├── DisplayConfigurationCoordinator.swift # Profile capture, reapply, sync checking
├── ProfileStore.swift                    # JSON persistence
├── DisplayManaging.swift                 # Protocols (DisplayManaging, Logger) + FileLogger
├── Debouncer.swift                       # Reusable debounce utility
└── Errors.swift                          # Typed error enums

DeskjockeyApp (macOS app target)
├── DeskjockeyAppMain.swift  # @main, single-instance lock, NSApplication.accessory
├── AppDelegate.swift        # Menu bar UI, display change orchestration
└── Runtime.swift            # CGDisplayReconfigurationCallback, MacDisplayManager, LoginItemManager
```

DeskjockeyCore has no AppKit/CoreGraphics dependency. All platform-specific code lives in
DeskjockeyApp.

## Version management

The version number appears in two places that must stay in sync:

| File | Field | Example |
|------|-------|---------|
| `project.yml` | `MARKETING_VERSION` | `"1.1.0"` |
| `CHANGELOG.md` | Section header | `## 1.1.0 - 2026-05-04` |

`CURRENT_PROJECT_VERSION` in `project.yml` is the build number. Increment it with each release.

The app reads its version at runtime from `CFBundleShortVersionString` (set by xcodebuild from
`MARKETING_VERSION`). The README menu bar example also shows the version — update it too.

SPM's `Package.swift` does not embed a version in the binary.

## Persistence

| Data | Location | Format |
|------|----------|--------|
| Profiles | `~/Library/Application Support/Deskjockey/profiles.json` | JSON array of `MonitorSetProfile` |
| Logs | `~/Library/Logs/Deskjockey/deskjockey.log` | Timestamped text (append-only) |
| Last processed timestamp | `UserDefaults` key `lastProcessedAt` | `Date` |
| Launch at login | `SMAppService.mainApp` | System-managed |

## Code signing

The app uses ad-hoc signing (`CODE_SIGN_IDENTITY: "-"`). Users installing from a zip must run
`xattr -cr /Applications/Deskjockey.app` to clear the quarantine flag. The Homebrew cask does
this automatically in its postflight script.

## Cutting a release

### 1. Prepare the release

```bash
# Update version in project.yml
# MARKETING_VERSION: "X.Y.Z"
# CURRENT_PROJECT_VERSION: increment by 1

# Move CHANGELOG.md "Unreleased" section to "## X.Y.Z - YYYY-MM-DD"
# Update README.md menu bar example if version is shown there
```

### 2. Build the release artifact

```bash
xcodegen generate
xcodebuild -project Deskjockey.xcodeproj -scheme Deskjockey -configuration Release build

# Create the zip
BUILD_DIR=$(xcodebuild -project Deskjockey.xcodeproj -scheme Deskjockey -configuration Release -showBuildSettings 2>/dev/null | grep ' BUILD_DIR' | awk '{print $3}')
cd "$BUILD_DIR/Release"
zip -r Deskjockey.zip Deskjockey.app

# Compute SHA256 for Homebrew
shasum -a 256 Deskjockey.zip
```

### 3. Create GitHub Release

- Go to https://github.com/JeroenvdV/Deskjockey/releases/new
- Tag: `vX.Y.Z` (e.g. `v1.1.0`)
- Title: `vX.Y.Z`
- Description: paste the CHANGELOG section for this version
- Attach `Deskjockey.zip`

### 4. Update Homebrew tap

The tap lives in a separate repo: `git@github.com:JeroenvdV/homebrew-deskjockey.git`

```bash
cd /path/to/homebrew-deskjockey   # clone of git@github.com:JeroenvdV/homebrew-deskjockey.git
```

Edit `Casks/deskjockey.rb`:
- Update `version` to the new version string (without `v` prefix)
- Update `sha256` to the hash from step 2

```ruby
cask "deskjockey" do
  version "X.Y.Z"
  sha256 "<sha256 from step 2>"
  # ... rest unchanged
end
```

Commit and push:
```bash
git add Casks/deskjockey.rb
git commit -m "Update to vX.Y.Z"
git push
```

Users can then install/upgrade with:
```bash
brew tap JeroenvdV/deskjockey
brew install --cask deskjockey
# or
brew upgrade --cask deskjockey
```

### Release checklist

- [ ] Version bumped in `project.yml` (MARKETING_VERSION + CURRENT_PROJECT_VERSION)
- [ ] CHANGELOG.md updated with date
- [ ] README.md menu example version updated
- [ ] `swift test` passes
- [ ] Release build succeeds
- [ ] Deskjockey.zip created and SHA256 noted
- [ ] GitHub Release created with tag `vX.Y.Z` and zip attached
- [ ] Homebrew tap updated with new version and SHA256
- [ ] `brew install --cask deskjockey` tested from clean state
