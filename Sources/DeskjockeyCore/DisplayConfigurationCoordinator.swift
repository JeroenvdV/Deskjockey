import Foundation

/// Abstraction for Task.sleep, injectable for tests.
public protocol SleepManaging {
    func sleep(milliseconds: UInt64) async
}

public struct TaskSleepManager: SleepManaging {
    public init() {}

    public func sleep(milliseconds: UInt64) async {
        try? await Task.sleep(nanoseconds: milliseconds * 1_000_000)
    }
}

/// Central coordinator for monitor profile management.
///
/// Responsibilities:
/// - Detect the current monitor set and match it to a saved profile
/// - Apply saved display positions and resolutions when monitors change
/// - Capture the current arrangement as a new or updated profile
///
/// All display interaction goes through the DisplayManaging protocol,
/// making this class fully testable without real hardware.
public final class DisplayConfigurationCoordinator {
    private let displayManager: DisplayManaging
    private let profileStore: MonitorProfileStoring
    private let sleepManager: SleepManaging
    private let logger: Logger
    private let reapplyDelayMilliseconds: UInt64
    private let now: () -> Date

    public init(
        displayManager: DisplayManaging,
        profileStore: MonitorProfileStoring,
        logger: Logger = NullLogger(),
        sleepManager: SleepManaging = TaskSleepManager(),
        reapplyDelayMilliseconds: UInt64 = 1_000,
        now: @escaping () -> Date = Date.init
    ) {
        self.displayManager = displayManager
        self.profileStore = profileStore
        self.logger = logger
        self.sleepManager = sleepManager
        self.reapplyDelayMilliseconds = reapplyDelayMilliseconds
        self.now = now
    }

    /// Called when the set of connected monitors changes (plug/unplug).
    /// Waits briefly for macOS to stabilize, then applies the saved profile
    /// for the current monitor set signature if one exists.
    public func monitorSetDidChange() async {
        // Brief delay to let macOS finish its own display reconfiguration.
        // Without this, we'd read stale display state.
        await sleepManager.sleep(milliseconds: reapplyDelayMilliseconds)

        let displays = displayManager.currentDisplays()
        guard !displays.isEmpty else {
            logger.info("No displays connected, skipping reapply")
            return
        }

        let signature = MonitorSetSignature.from(displays: displays)
        let sorted = displays.sorted {
            if $0.frame.origin.x != $1.frame.origin.x { return $0.frame.origin.x < $1.frame.origin.x }
            if $0.frame.origin.y != $1.frame.origin.y { return $0.frame.origin.y < $1.frame.origin.y }
            return $0.runtimeID < $1.runtimeID
        }
        var summary = "Monitor set changed (\(displays.count) display(s), signature: \(signature.rawValue))"
        for display in sorted {
            let tag = display.isBuiltIn ? " (built-in)" : ""
            let res = "\(display.resolution.width)x\(display.resolution.height)"
            let origin = "(\(display.frame.origin.x), \(display.frame.origin.y))"
            summary += "\n  #\(display.runtimeID) \(display.normalizedModelName)\(tag)  \(res)  at \(origin)"
        }
        logger.info(summary)

        let allProfiles: [MonitorSetProfile]
        do {
            allProfiles = try profileStore.loadProfiles()
        } catch {
            logger.error("Failed to load profiles: \(error)")
            return
        }

        guard let profile = allProfiles.first(where: { $0.signature == signature }) else {
            logger.info("No saved profile for signature \(signature.rawValue)")
            return
        }

        let pairs = DisplayMatcher.pair(liveDisplays: displays, profileSlots: profile.slots)
        logger.info("Applying profile with \(pairs.count) display(s)")

        // Update lastUsedAt for this profile
        recordProfileUsed()

        for pair in pairs {
            let displayLabel = Self.label(for: pair.display)
            let targetOrigin = "(\(pair.slot.targetFrame.origin.x), \(pair.slot.targetFrame.origin.y))"

            // Built-in display: only reposition, skip resolution.
            // macOS manages the built-in's scaling based on user preferences in
            // System Settings, and the available modes change depending on which
            // external monitors are connected. Attempting to set the resolution
            // would either fail or be a no-op.
            if pair.display.isBuiltIn {
                logger.info("Configuring \(displayLabel): origin \(targetOrigin) (resolution managed by macOS)")
                let config = DisplayConfiguration(
                    runtimeID: pair.display.runtimeID,
                    targetFrame: pair.slot.targetFrame,
                    targetResolution: pair.display.resolution
                )
                do {
                    try displayManager.apply(configuration: config, to: pair.display)
                    logger.info("Applied position to \(displayLabel)")
                } catch {
                    logger.error("Failed to configure \(displayLabel): \(error)")
                }
            } else {
                let targetRes = "\(pair.slot.targetResolution.width)x\(pair.slot.targetResolution.height)"
                logger.info("Configuring \(displayLabel): origin \(targetOrigin), resolution \(targetRes)")
                let config = DisplayConfiguration(
                    runtimeID: pair.display.runtimeID,
                    targetFrame: pair.slot.targetFrame,
                    targetResolution: pair.slot.targetResolution
                )
                do {
                    try displayManager.apply(configuration: config, to: pair.display)
                    logger.info("Applied config to \(displayLabel)")
                } catch {
                    logger.error("Failed to configure \(displayLabel): \(error)")
                }
            }
        }
    }

    /// Snapshots the current display arrangement and saves it as the profile
    /// for the current monitor set signature. Overwrites any existing profile
    /// for the same signature.
    public func captureCurrentSetup() throws {
        let displays = displayManager.currentDisplays()
        guard !displays.isEmpty else {
            throw ProfileError.noDisplaysConnected
        }

        let signature = MonitorSetSignature.from(displays: displays)
        let resolutionSignature = ResolutionSetSignature.from(displays: displays)
        let slots = SlotPlanner.indexedSlots(for: displays)
            .flatMap { modelName, indexed in
                indexed.map { item in
                    MonitorSlotProfile(
                        modelName: modelName,
                        slotIndex: item.slotIndex,
                        targetFrame: item.display.frame,
                        targetResolution: item.display.resolution
                    )
                }
            }
            .sorted {
                if $0.modelName != $1.modelName { return $0.modelName < $1.modelName }
                return $0.slotIndex < $1.slotIndex
            }

        let newProfile = MonitorSetProfile(
            signature: signature,
            slots: slots,
            updatedAt: now(),
            lastUsedAt: nil,
            resolutionSignature: resolutionSignature
        )

        do {
            var profiles = try profileStore.loadProfiles()
            profiles.removeAll { $0.signature == signature }
            profiles.append(newProfile)
            try profileStore.saveProfiles(profiles)
            var msg = "Profile saved (\(slots.count) display(s), signature: \(signature.rawValue))"
            for slot in slots {
                let res = "\(slot.targetResolution.width)x\(slot.targetResolution.height)"
                let origin = "(\(slot.targetFrame.origin.x), \(slot.targetFrame.origin.y))"
                msg += "\n  \(slot.modelName)#\(slot.slotIndex)  \(res)  at \(origin)"
            }
            logger.info(msg)
        } catch {
            logger.error("Failed to save profile: \(error)")
            throw ProfileError.storageFailure(underlying: error)
        }
    }

    /// Returns true if a saved profile exists for the current monitor set.
    public func hasSavedProfile() -> Bool {
        guard let signature = currentSignature() else { return false }
        let profiles = (try? profileStore.loadProfiles()) ?? []
        return profiles.contains { $0.signature == signature }
    }

    /// Human-readable label for log output: "DELL P3223QE [3840x2160]"
    private static func label(for display: DisplaySnapshot) -> String {
        let tag = display.isBuiltIn ? " (built-in)" : ""
        let res = "\(display.resolution.width)x\(display.resolution.height)"
        return "\(display.normalizedModelName)\(tag) [\(res)]"
    }

    public func currentSignature() -> MonitorSetSignature? {
        let displays = displayManager.currentDisplays()
        guard !displays.isEmpty else { return nil }
        return MonitorSetSignature.from(displays: displays)
    }

    /// Returns ordered display summaries for the menu bar UI.
    /// Each summary indicates whether that display's current state matches
    /// the saved profile. For built-in displays, only position is compared
    /// (resolution is managed by macOS and varies with connected externals).
    public func displaySummaries() -> [DisplaySummary] {
        let displays = displayManager.currentDisplays()
        guard !displays.isEmpty else { return [] }

        let signature = MonitorSetSignature.from(displays: displays)
        let savedProfile = (try? profileStore.loadProfiles())?.first { $0.signature == signature }
        let pairs: [(display: DisplaySnapshot, slot: MonitorSlotProfile)]?
        if let savedProfile {
            pairs = DisplayMatcher.pair(liveDisplays: displays, profileSlots: savedProfile.slots)
        } else {
            pairs = nil
        }

        // Sort left-to-right, top-to-bottom -- consistent with SlotPlanner ordering
        let sorted = displays.sorted {
            if $0.frame.origin.x != $1.frame.origin.x { return $0.frame.origin.x < $1.frame.origin.x }
            if $0.frame.origin.y != $1.frame.origin.y { return $0.frame.origin.y < $1.frame.origin.y }
            return $0.runtimeID < $1.runtimeID
        }

        return sorted.map { display in
            let matchesSaved: Bool
            if let pairs, let pair = pairs.first(where: { $0.display.runtimeID == display.runtimeID }) {
                if display.isBuiltIn {
                    // Only compare position for built-in displays
                    matchesSaved = display.frame == pair.slot.targetFrame
                } else {
                    matchesSaved = display.frame == pair.slot.targetFrame
                        && display.resolution == pair.slot.targetResolution
                }
            } else {
                matchesSaved = false
            }
            return DisplaySummary(
                modelName: display.normalizedModelName,
                resolution: display.resolution,
                isBuiltIn: display.isBuiltIn,
                matchesSaved: matchesSaved
            )
        }
    }

    /// Returns true if all current displays match their saved profile slots.
    public func currentSetupMatchesSaved() -> Bool {
        let summaries = displaySummaries()
        guard !summaries.isEmpty else { return false }
        return summaries.allSatisfy(\.matchesSaved)
    }

    // MARK: - Copy Similar Setup

    /// Returns profiles that match the current display setup's resolution signature.
    /// Used for the "Copy Similar Setup" feature. Only returns profiles that have
    /// a matching resolution signature but a different model signature.
    public func findProfilesMatchingResolutionSignature() -> [MonitorSetProfile] {
        let currentDisplays = displayManager.currentDisplays()
        guard !currentDisplays.isEmpty else {
            return []
        }

        let currentResolutionSignature = ResolutionSetSignature.from(displays: currentDisplays)
        let currentModelSignature = MonitorSetSignature.from(displays: currentDisplays)

        let allProfiles = (try? profileStore.loadProfiles()) ?? []

        // Find profiles with matching resolution signature but different model signature
        return allProfiles.filter { profile in
            profile.resolutionSignature == currentResolutionSignature
                && profile.signature != currentModelSignature
        }
    }

    /// Copies a profile's slots to create a new profile for the current monitor set.
    /// This is used for the "Copy Similar Setup" feature when you connect to a new
    /// setup that has the same native resolutions as an existing setup.
    /// 
    /// - Parameter sourceProfile: The profile to copy slots from
    /// - Throws: ProfileError if no displays are connected
    public func copyProfileFromSimilarSetup(sourceProfile: MonitorSetProfile) throws {
        let displays = displayManager.currentDisplays()
        guard !displays.isEmpty else {
            throw ProfileError.noDisplaysConnected
        }

        let currentSignature = MonitorSetSignature.from(displays: displays)
        let currentResolutionSignature = ResolutionSetSignature.from(displays: displays)

        // Sort both the source slots and current displays by position
        let sortedSourceSlots = sourceProfile.slots.sorted {
            if $0.targetFrame.origin.x != $1.targetFrame.origin.x {
                return $0.targetFrame.origin.x < $1.targetFrame.origin.x
            }
            return $0.targetFrame.origin.y < $1.targetFrame.origin.y
        }

        let sortedDisplays = displays.sorted {
            if $0.frame.origin.x != $1.frame.origin.x {
                return $0.frame.origin.x < $1.frame.origin.x
            }
            return $0.frame.origin.y < $1.frame.origin.y
        }

        // Create new slots by mapping source slots to current displays by position
        // This assumes displays are in the same relative positions
        let slots: [MonitorSlotProfile]
        if sortedSourceSlots.count == sortedDisplays.count {
            slots = zip(sortedSourceSlots, sortedDisplays).map { (sourceSlot, display) in
                MonitorSlotProfile(
                    modelName: display.normalizedModelName,
                    slotIndex: sourceSlot.slotIndex,
                    targetFrame: sourceSlot.targetFrame,
                    targetResolution: sourceSlot.targetResolution
                )
            }
        } else {
            // Fallback: use current display positions but try to match by resolution
            // Pair displays with source slots that have the same target resolution
            slots = sortedDisplays.enumerated().map { index, display in
                let matchingSlot = sortedSourceSlots.first { $0.targetResolution == display.resolution }
                return MonitorSlotProfile(
                    modelName: display.normalizedModelName,
                    slotIndex: index,
                    targetFrame: matchingSlot?.targetFrame ?? display.frame,
                    targetResolution: matchingSlot?.targetResolution ?? display.resolution
                )
            }
        }

        let newProfile = MonitorSetProfile(
            signature: currentSignature,
            slots: slots,
            updatedAt: now(),
            lastUsedAt: nil,
            resolutionSignature: currentResolutionSignature
        )

        // Save the new profile
        do {
            var profiles = try profileStore.loadProfiles()
            profiles.removeAll { $0.signature == currentSignature }
            profiles.append(newProfile)
            try profileStore.saveProfiles(profiles)
            logger.info("Copied profile from similar setup with signature: \(sourceProfile.signature.rawValue)")
        } catch {
            logger.error("Failed to save copied profile: \(error)")
            throw ProfileError.storageFailure(underlying: error)
        }
    }

    /// Returns the most recently used profile that matches the current resolution signature.
    /// Used for the "Copy Similar Setup" feature.
    public func findMostRecentMatchingProfileByResolution() -> MonitorSetProfile? {
        let matchingProfiles = findProfilesMatchingResolutionSignature()
        
        // Sort by lastUsedAt descending, then by updatedAt descending
        let sorted = matchingProfiles.sorted { lhs, rhs in
            let lhsDate = lhs.lastUsedAt ?? lhs.updatedAt
            let rhsDate = rhs.lastUsedAt ?? rhs.updatedAt
            return lhsDate > rhsDate
        }
        
        return sorted.first
    }

    /// Checks if there's at least one profile that matches the current resolution signature.
    public func hasSimilarSetupByResolution() -> Bool {
        return !findProfilesMatchingResolutionSignature().isEmpty
    }

    // MARK: - Profile Usage Tracking

    /// Updates the lastUsedAt date for the profile matching the current signature.
    /// Called when a profile is successfully applied.
    public func recordProfileUsed() {
        guard let currentSignature = currentSignature() else { return }
        
        do {
            var profiles = try profileStore.loadProfiles()
            if let index = profiles.firstIndex(where: { $0.signature == currentSignature }) {
                profiles[index].lastUsedAt = now()
                // Also ensure resolution signature is set for backward compatibility
                if profiles[index].resolutionSignatureRawValue == nil {
                    let displays = displayManager.currentDisplays()
                    let resolutionSignature = ResolutionSetSignature.from(displays: displays)
                    profiles[index].resolutionSignatureRawValue = resolutionSignature.rawValue
                }
                try profileStore.saveProfiles(profiles)
            }
        } catch {
            logger.error("Failed to update profile usage: \(error)")
        }
    }

    /// Migrates existing profiles to add resolution signatures if they don't have them.
    /// Ensures backward compatibility with older config files.
    public func migrateProfilesIfNeeded() {
        do {
            var profiles = try profileStore.loadProfiles()
            var needsSave = false
            
            for i in 0..<profiles.count {
                if profiles[i].resolutionSignatureRawValue == nil {
                    // We can't compute the resolution signature without the original displays,
                    // but we can set it based on the slots' resolutions
                    let resolutionCounts = Dictionary(grouping: profiles[i].slots, by: { $0.targetResolution })
                        .mapValues { $0.count }
                    let sortedResolutions = resolutionCounts.keys.sorted { lhs, rhs in
                        let lhsArea = lhs.width * lhs.height
                        let rhsArea = rhs.width * rhs.height
                        if lhsArea != rhsArea { return lhsArea > rhsArea }
                        if lhs.width != rhs.width { return lhs.width > rhs.width }
                        return lhs.height > rhs.height
                    }
                    let signature = ResolutionSetSignature(rawValue: sortedResolutions.map { 
                        "\($0.width)x\($0.height)x\(resolutionCounts[$0] ?? 0)" 
                    }.joined(separator: "|"))
                    profiles[i].resolutionSignatureRawValue = signature.rawValue
                    needsSave = true
                }
            }
            
            if needsSave {
                try profileStore.saveProfiles(profiles)
                logger.info("Migrated profiles to add resolution signatures")
            }
        } catch {
            logger.error("Failed to migrate profiles: \(error)")
        }
    }
}
