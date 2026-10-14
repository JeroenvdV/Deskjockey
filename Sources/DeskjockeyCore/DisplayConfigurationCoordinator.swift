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
        let sortedForLog = displays.sorted {
            if $0.normalizedModelName != $1.normalizedModelName { return $0.normalizedModelName < $1.normalizedModelName }
            return $0.serialNumber < $1.serialNumber
        }
        var summary = "Monitor set changed (\(displays.count) display(s), signature: \(signature.rawValue))"
        for display in sortedForLog {
            let tag = display.isBuiltIn ? " (built-in)" : ""
            let res = "\(display.resolution.width)x\(display.resolution.height)"
            let origin = "(\(display.frame.origin.x), \(display.frame.origin.y))"
            summary += "\n  #\(display.runtimeID) \(display.normalizedModelName)\(tag)  \(res)  at \(origin)  serial:\(display.serialNumber) port:\(display.portIdentifier)"
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

        let (pairs, assignment) = SlotResolver.pair(
            liveDisplays: displays,
            profileSlots: profile.slots,
            knownAssignments: profile.knownAssignments,
            now: now()
        )
        logger.info("Applying profile with \(pairs.count) display(s)")

        // Update lastUsedAt and record slot assignment for this profile
        recordProfileUsed(assignment: assignment)

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
                    targetFrame: DisplayFrame(
                        origin: pair.slot.targetFrame.origin,
                        size: pair.display.frame.size
                    ),
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

    /// Called when macOS changes the arrangement of the same set of monitors.
    ///
    /// If a display changed size (the user picked another resolution), macOS has
    /// moved it to a spot of its own choosing. This moves the displays back into
    /// the saved arrangement first. Then it saves the current arrangement.
    public func configurationDidChange() throws {
        let displays = displayManager.currentDisplays()
        guard !displays.isEmpty else {
            throw ProfileError.noDisplaysConnected
        }

        let signature = MonitorSetSignature.from(displays: displays)
        if let profile = try? profileStore.loadProfiles().first(where: { $0.signature == signature }) {
            restoreArrangementAfterResize(displays: displays, profile: profile)
        }
        try captureCurrentSetup()
    }

    private func restoreArrangementAfterResize(displays: [DisplaySnapshot], profile: MonitorSetProfile) {
        let pairs = SlotResolver.pair(
            liveDisplays: displays,
            profileSlots: profile.slots,
            knownAssignments: profile.knownAssignments
        ).pairs
        let resized = pairs.filter {
            $0.display.frame.size != $0.slot.targetFrame.size || $0.display.resolution != $0.slot.targetResolution
        }
        guard !resized.isEmpty else { return }

        let savedLayout = profile.savedLayout(matching: pairs)
        let targets = ResizeLayout.targetOrigins(pairs: pairs, savedLayout: savedLayout)
        let moves = targets.filter { runtimeID, origin in
            displays.first { $0.runtimeID == runtimeID }?.frame.origin != origin
        }

        var msg = "Display size changed, "
        msg += savedLayout == nil ? "keeping arrangement" : "restoring saved arrangement for these sizes"
        for pair in resized {
            let size = pair.display.frame.size
            msg += "\n  \(Self.label(for: pair.display))  now \(size.width)x\(size.height) points"
        }
        for pair in pairs {
            guard let origin = moves[pair.display.runtimeID] else { continue }
            msg += "\n  moving \(Self.label(for: pair.display)) to (\(origin.x), \(origin.y))"
        }
        logger.info(msg)
        guard !moves.isEmpty else { return }

        do {
            try displayManager.moveDisplays(to: moves)
        } catch {
            logger.error("Failed to move displays: \(error)")
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

        do {
            var profiles = try profileStore.loadProfiles()
            let existingProfile = profiles.first(where: { $0.signature == signature })
            let existingLastUsedAt = existingProfile?.lastUsedAt
            var assignments = existingProfile?.knownAssignments ?? []

            let resolution = SlotResolver.resolve(
                displays: displays,
                knownAssignments: assignments,
                now: now()
            )

            let slots = resolution.pairs
                .map { display, slotIndex in
                    MonitorSlotProfile(
                        modelName: display.matchingModelName,
                        slotIndex: slotIndex,
                        targetFrame: display.frame,
                        targetResolution: display.resolution
                    )
                }
                .sorted {
                    if $0.modelName != $1.modelName { return $0.modelName < $1.modelName }
                    return $0.slotIndex < $1.slotIndex
                }

            assignments.upsert(resolution.assignment)
            profiles.removeAll { $0.signature == signature }

            var newProfile = MonitorSetProfile(
                signature: signature,
                slots: slots,
                knownAssignments: assignments,
                updatedAt: now(),
                lastUsedAt: existingLastUsedAt,
                resolutionSignature: resolutionSignature,
                savedLayouts: existingProfile?.savedLayouts ?? []
            )
            if let existingProfile {
                newProfile.rememberLayout(existingProfile.slots)
            }
            newProfile.rememberLayout(slots)
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
            let result = SlotResolver.pair(
                liveDisplays: displays,
                profileSlots: savedProfile.slots,
                knownAssignments: savedProfile.knownAssignments
            )
            pairs = result.pairs
        } else {
            pairs = nil
        }

        // Resolve slot indices for consistent ordering (model name, then slot index).
        let resolution = SlotResolver.resolve(
            displays: displays,
            knownAssignments: savedProfile?.knownAssignments ?? []
        )
        let slotIndexByRuntimeID = Dictionary(
            uniqueKeysWithValues: resolution.pairs.map { ($0.display.runtimeID, $0.slotIndex) }
        )
        let sorted = displays.sorted {
            if $0.matchingModelName != $1.matchingModelName {
                return $0.matchingModelName < $1.matchingModelName
            }
            let lhsSlot = slotIndexByRuntimeID[$0.runtimeID] ?? 0
            let rhsSlot = slotIndexByRuntimeID[$1.runtimeID] ?? 0
            return lhsSlot < rhsSlot
        }

        return sorted.map { display in
            let matchesSaved: Bool
            if let pairs, let pair = pairs.first(where: { $0.display.runtimeID == display.runtimeID }) {
                if display.isBuiltIn {
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

        // Pair source slots with current displays by resolution (canonical ordering).
        // Position is output of the application and must never be used as input.
        // Both sides are sorted by resolution (DisplaySize.Comparable), then model
        // name, producing a stable pairing regardless of physical arrangement.
        let sortedSourceSlots = sourceProfile.slots.sorted {
            if $0.targetResolution != $1.targetResolution { return $0.targetResolution < $1.targetResolution }
            return $0.modelName < $1.modelName
        }
        let sortedDisplays = displays.sorted {
            if $0.resolution != $1.resolution { return $0.resolution < $1.resolution }
            return $0.matchingModelName < $1.matchingModelName
        }

        var slots: [MonitorSlotProfile] = []
        var assignmentEntries: [SlotAssignmentEntry] = []
        for (sourceSlot, display) in zip(sortedSourceSlots, sortedDisplays) {
            slots.append(MonitorSlotProfile(
                modelName: display.matchingModelName,
                slotIndex: sourceSlot.slotIndex,
                targetFrame: sourceSlot.targetFrame,
                targetResolution: sourceSlot.targetResolution
            ))
            assignmentEntries.append(SlotAssignmentEntry(
                modelName: display.matchingModelName,
                slotIndex: sourceSlot.slotIndex,
                serialNumber: display.serialNumber,
                portIdentifier: display.portIdentifier
            ))
        }
        let assignment = SlotAssignment(entries: assignmentEntries, lastUsedAt: now())

        // Save the new profile
        do {
            var profiles = try profileStore.loadProfiles()
            let existingProfile = profiles.first(where: { $0.signature == currentSignature })
            let existingLastUsedAt = existingProfile?.lastUsedAt
            var assignments = existingProfile?.knownAssignments ?? []
            assignments.upsert(assignment)
            profiles.removeAll { $0.signature == currentSignature }

            let newProfile = MonitorSetProfile(
                signature: currentSignature,
                slots: slots,
                knownAssignments: assignments,
                updatedAt: now(),
                lastUsedAt: existingLastUsedAt,
                resolutionSignature: currentResolutionSignature
            )
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

    /// Updates the lastUsedAt date and optionally records a slot assignment
    /// for the profile matching the current signature.
    private func recordProfileUsed(assignment: SlotAssignment? = nil) {
        guard let currentSignature = currentSignature() else { return }
        
        do {
            var profiles = try profileStore.loadProfiles()
            if let index = profiles.firstIndex(where: { $0.signature == currentSignature }) {
                profiles[index].lastUsedAt = now()
                if let assignment {
                    profiles[index].knownAssignments.upsert(assignment)
                }
                if profiles[index].resolutionSignatureRawValue == nil {
                    let displays = displayManager.currentDisplays()
                    profiles[index].resolutionSignatureRawValue = ResolutionSetSignature.from(displays: displays).rawValue
                }
                try profileStore.saveProfiles(profiles)
            }
        } catch {
            logger.error("Failed to update profile usage: \(error)")
        }
    }

    /// Migrates existing profiles to canonical formats:
    /// - Resolution signatures: canonical DisplaySize.Comparable ordering
    /// - Built-in display names: collapsed to "Built-in Display" in slots,
    ///   assignments, and signatures
    public func migrateProfilesIfNeeded() {
        do {
            var profiles = try profileStore.loadProfiles()
            var needsSave = false
            let builtInCanonical = "Built-in Display"
            
            for i in 0..<profiles.count {
                // Canonicalize built-in display names in slot profiles
                for j in 0..<profiles[i].slots.count {
                    if profiles[i].slots[j].modelName.hasPrefix("Built-in")
                        && profiles[i].slots[j].modelName != builtInCanonical {
                        profiles[i].slots[j].modelName = builtInCanonical
                        needsSave = true
                    }
                }

                // Canonicalize built-in display names in known assignments
                for j in 0..<profiles[i].knownAssignments.count {
                    for k in 0..<profiles[i].knownAssignments[j].entries.count {
                        if profiles[i].knownAssignments[j].entries[k].modelName.hasPrefix("Built-in")
                            && profiles[i].knownAssignments[j].entries[k].modelName != builtInCanonical {
                            profiles[i].knownAssignments[j].entries[k].modelName = builtInCanonical
                            needsSave = true
                        }
                    }
                }

                // Recompute signature if it contains a non-canonical built-in name
                if profiles[i].signatureRawValue.contains("Built-in")
                    && !profiles[i].signatureRawValue.contains("Built-in Displayx") {
                    let counts = Dictionary(grouping: profiles[i].slots, by: { $0.modelName })
                        .mapValues { $0.count }
                    let canonical = counts.keys.sorted().map { "\($0)x\(counts[$0] ?? 0)" }
                        .joined(separator: "|")
                    profiles[i].signatureRawValue = canonical
                    needsSave = true
                }

                // Recompute resolution signature using canonical ordering
                let resolutionCounts = Dictionary(grouping: profiles[i].slots, by: { $0.targetResolution })
                    .mapValues { $0.count }
                let canonical = resolutionCounts.keys.sorted().map {
                    "\($0.width)x\($0.height)x\(resolutionCounts[$0] ?? 0)"
                }.joined(separator: "|")

                if profiles[i].resolutionSignatureRawValue != canonical {
                    profiles[i].resolutionSignatureRawValue = canonical
                    needsSave = true
                }
            }

            // Deduplicate profiles that now have the same signature after
            // built-in name canonicalization (keep most recently updated)
            if needsSave {
                var seen: [String: Int] = [:]
                var toRemove: [Int] = []
                for i in 0..<profiles.count {
                    if let existing = seen[profiles[i].signatureRawValue] {
                        // Keep the one with the more recent updatedAt
                        if profiles[i].updatedAt > profiles[existing].updatedAt {
                            toRemove.append(existing)
                            seen[profiles[i].signatureRawValue] = i
                        } else {
                            toRemove.append(i)
                        }
                    } else {
                        seen[profiles[i].signatureRawValue] = i
                    }
                }
                for index in toRemove.sorted().reversed() {
                    profiles.remove(at: index)
                }
            }
            
            if needsSave {
                try profileStore.saveProfiles(profiles)
                logger.info("Migrated profiles (built-in name canonicalization, resolution signatures)")
            }
        } catch {
            logger.error("Failed to migrate profiles: \(error)")
        }
    }
}
