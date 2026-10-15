# Development Guide

See [Intended behavior](BEHAVIOR.md) for the class, instance, and screen configuration definitions, plus the differences from the current implementation.

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
├── DisplaySetModels.swift                          # Typed model IDs, classes, instances, slots, and plans
├── ScreenConfigurationLogic.swift              # Pure validation, capture, and permutation detection
├── SlotAssignmentResolver.swift                    # Exact instance and complete fallback assignment
├── ScreenConfigurationCoordinator.swift # Serialized capture, apply, readback, and persistence
├── DisplaySetPresentation.swift             # Menu state from domain data
├── DetectionLog.swift                    # Correlated structured diagnostics
├── LegacyProfileMigration.swift          # Conservative live conversion of legacy profiles
├── DisplaySetStore.swift                    # Versioned persistence, validation, and backups
├── DisplayManaging.swift                 # Protocols (DisplayManaging, Logger) + FileLogger
├── Debouncer.swift                       # Reusable debounce utility
└── DisplaySetError.swift                          # Typed error enums

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
| Display set database | `~/Library/Application Support/Deskjockey/profiles.json` | Version-two `DisplaySetDatabase` JSON envelope with display set classes and retained legacy records |
| Legacy backup | `~/Library/Application Support/Deskjockey/profiles.json.v1-backup` | Original version-one bytes, preserved before conversion |
| Logs | `~/Library/Logs/Deskjockey/deskjockey.log` | Timestamped text (append-only) |
| Last processed timestamp | `UserDefaults` key `lastProcessedAt` | `Date` |
| Launch at login | `SMAppService.mainApp` | System-managed |

The class key derives from sorted vendor/product IDs with multiplicity. Names never define display set class identity.
Instances use complete, distinct model-and-serial identities; missing or duplicate serials permit session-only assignments.
Unknown classes are captured at launch and on connection. External edits update the class unless they are pure slot permutations.

The store accepts version-one arrays without changing them on read.
A save preserves legacy records and the original file backup before writing the version-two envelope atomically.
If a backup already exists with different bytes, the store creates an additional uniquely named backup.
Unsupported schemas, corrupt data, and detected external edits prevent a save.
The store does not silently merge legacy layouts or infer model identity from name suffixes.

The coordinator owns a serialized cycle on the main actor. It validates observed results before recording a successful restore.
Display callbacks retain their IDs and flags; connection events invalidate session-only assignments.
Diagnostic JSON records share a detection ID and include reason codes, observations, assignments, and outcomes.
Display failures produce no user-facing alerts.

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

---

## Coding Guidelines

### Architecture Principles

1. **Separation of Concerns**: DeskjockeyCore contains zero AppKit/CoreGraphics dependencies. All platform-specific code lives in DeskjockeyApp. This allows the core logic to be tested without hardware and potentially reused for other platforms.

2. **Dependency Injection**: Use protocols for all external dependencies (DisplayManaging, DisplaySetStoring, Logger, SleepManaging). This enables full testability with mock objects.

3. **Single Responsibility**: Each class should have one clear responsibility. If a class grows beyond ~300 lines or has more than 5-6 public methods, consider splitting it.

4. **Immutability First**: Prefer value types (structs) over reference types (classes) for data models. Use `let` for properties that don't need to change.

5. **Error Handling**: Use typed errors (enums conforming to Error) rather than strings or raw error codes. Provide descriptive `CustomStringConvertible` implementations.

### Domain vocabulary

Use the same domain terms in types, methods, tests, documentation, and diagnostics.

| Concept | Canonical name |
| --- | --- |
| Hardware model identity | `DisplayModelID` |
| Physical device identity | `DisplayDeviceID` |
| Model collection and shared settings | `DisplaySetClass` |
| Physical device collection and slot assignments | `DisplaySetInstance` |
| Shared settings for all slots | `ScreenConfiguration` |
| One device-to-slot assignment | `DisplaySlotAssignment` |
| Assignment algorithm result | `SlotAssignmentResult` |
| One display's apply command | `DisplayApplyTarget` |
| Complete apply command | `DisplayApplyPlan` |
| Storage model | `DisplaySetDatabase.classes` |
| Storage boundary | `DisplaySetStoring` and `JSONDisplaySetStore` |

Use `displayName` for presentation names and `pixelSize` for pixel dimensions.
Do not call an assignment result a resolution or a class a setup.
Diagnostic field names identify their values explicitly, such as `detection_id`, `class_id`, and `slot_id`.
Emit `instance_saved` only after a successful database save; `instance_identified` records identity evidence before that save.

Compatibility exceptions are deliberate:
- The filename `profiles.json` remains unchanged.
- The version-two JSON key `profiles` maps to `classes` through `CodingKeys`.
- Version-one names remain inside `LegacyProfileMigration` and its compatibility fixtures.
- Apple API symbols and historical release notes keep their original names.

### Code Style

#### Naming
- Use **PascalCase** for types, protocols, enums
- Use **camelCase** for variables, functions, properties
- Use **UPPER_CAMEL_CASE** for constants and static properties
- Name types for what they **are** (nouns): `DisplaySnapshot`, `DisplaySetClass`
- Name functions for what they **do** (verbs): `captureCurrentScreenConfiguration()`, `applyConfiguration()`
- Name booleans to read like assertions: `hasSavedScreenConfiguration`, `isBuiltIn`, `matchesScreenConfiguration`

#### Formatting
- **Indentation**: 4 spaces (Xcode default)
- **Line length**: Aim for 100-120 characters, but don't break readability
- **Braces**: Opening brace on same line for functions, types, control flow
- **Spacing**: One blank line between logical sections, no blank lines within related code

#### Organization
- Group related functionality with `// MARK: - ` comments
- Order: Properties, Initializers, Public methods, Private methods
- Use extensions to organize conformances and related functionality

### Testing

#### Test Structure
- **File naming**: `*Tests.swift` suffix (e.g., `DisplaySetStoreTests.swift`)
- **Test class naming**: `*Tests` suffix (e.g., `DisplaySetStoreTests`)
- **Test method naming**: Start with `test` followed by descriptive name in camelCase

#### Test Coverage
- **Target**: Maintain >80% line coverage, >70% function coverage in DeskjockeyCore
- **Focus**: All public APIs should be tested; critical paths (persistence, error handling) must have tests
- **Mock objects**: Use protocols for mocking; keep mocks simple and focused

#### Test Quality
- **Isolation**: Each test should set up its own dependencies and not rely on shared state
- **Determinism**: Tests should be deterministic (same input always produces same output)
- **Speed**: Tests should run quickly; avoid sleep/wait in tests when possible
- **Clarity**: Test names should clearly describe the behavior being tested

### Common Patterns

#### Identity and assignment order
Use typed model and device identities, not display labels, for comparisons.
Use `SlotAssignmentResolver` for assignments and deterministic fallback order.
Do not infer a new instance's assignment from current positions.
`ScreenConfigurationLogic.permutation` may compare positions only to classify an edit to an existing configuration.

#### Constants
Define magic numbers and strings as constants:
```swift
private enum Constants {
    static let debounceDelay: TimeInterval = 0.8
    static let reapplyDelayMilliseconds: UInt64 = 1_000
    static let statusIconFlashDuration: TimeInterval = 0.8
}
```

#### Error Handling
Prefer typed errors with descriptive messages:
```swift
public enum DisplaySetError: Error, CustomStringConvertible {
    case operationFailed(String)

    public var description: String {
        switch self {
        case .operationFailed(let reason):
            return "Display set operation failed: \(reason)"
        }
    }
}
```

#### Logging
Use the Logger protocol for all logging:
```swift
let log = DetectionLog(logger: logger)
log.info("class_detection", ["class_id": classID.description])
log.error("operation_failed", ["error": String(describing: error)])
```
Avoid `print()` statements in production code.

### File Organization

| File | Purpose |
|------|---------|
| `DisplaySetModels.swift` | Typed identities, geometry, and screen configurations |
| `ScreenConfigurationCoordinator.swift` | Class detection, configuration capture, and restore |
| `DisplaySetStore.swift` | JSON persistence layer |
| `DisplayManaging.swift` | Protocols and logging implementations |
| `DisplaySetError.swift` | Typed error definitions |
| `Debouncer.swift` | Event coalescing utility |
| `Runtime.swift` | Platform-specific implementations (macOS) |
| `AppDelegate.swift` | App lifecycle, menu management, display change handling |

---

## Contributing

### Before Submitting a PR

1. **Run tests**: Ensure all tests pass with `swift test`
2. **Check coverage**: New code should have corresponding tests; maintain existing coverage levels
3. **Follow style**: Use the coding guidelines above
4. **Update docs**: If you change user-facing behavior, update README.md
5. **Squash commits**: Rebase and squash into logical commits before merging

### PR Template

```
## Description

[What this PR does]

## Changes

- [ ] Bug fix
- [ ] New feature
- [ ] Refactoring
- [ ] Documentation
- [ ] Tests

## Testing

- [ ] All existing tests pass
- [ ] New tests added for new functionality
- [ ] Manual testing performed

## Checklist

- [ ] Code follows coding guidelines
- [ ] Tests pass
- [ ] Documentation updated (if applicable)
```

### Review Process

1. All PRs require at least one approval
2. CI must pass (tests + build)
3. Code review focuses on: correctness, clarity, maintainability, test coverage
4. Address review comments before merging
