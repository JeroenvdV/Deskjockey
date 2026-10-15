import Foundation

public protocol SleepManaging {
    func sleep(milliseconds: UInt64) async
}
public struct TaskSleepManager: SleepManaging {
    public init() {}
    public func sleep(milliseconds: UInt64) async { try? await Task.sleep(nanoseconds: milliseconds * 1_000_000) }
}

/// Owns one serialized observation/apply/persistence cycle. The UI never owns transaction state.
@MainActor
public final class ScreenConfigurationCoordinator {
    private let displayManager: DisplayManaging
    private let displaySetStore: DisplaySetStoring
    private let logger: Logger
    private let sleepManager: SleepManaging
    private let delay: UInt64
    private let now: () -> Date
    private var busy = false
    private var pendingObservation = false
    private var connectionInvalidated = false
    private var lastObserved: [DisplaySnapshot]?
    private var sessionMapping: [String: Int] = [:]
    public private(set) var state = DisplaySetState()

    private enum Command { case observe, capture, restore, swap(String, String) }

    private func commandName(_ command: Command) -> String {
        switch command {
        case .observe: return "observe"
        case .capture: return "capture"
        case .restore: return "restore"
        case .swap: return "swap"
        }
    }

    public init(displayManager: DisplayManaging, displaySetStore: DisplaySetStoring,
                logger: Logger = NullLogger(), sleepManager: SleepManaging = TaskSleepManager(),
                reapplyDelayMilliseconds: UInt64 = 1_000, now: @escaping () -> Date = Date.init) {
        self.displayManager = displayManager; self.displaySetStore = displaySetStore; self.logger = logger
        self.sleepManager = sleepManager; delay = reapplyDelayMilliseconds; self.now = now
    }

    /// Connection callbacks invalidate session-only identities even if a driver reuses runtime IDs.
    public func displayConnectionDidChange() {
        DetectionLog(logger: logger).debug("connection_invalidated")
        connectionInvalidated = true
        if busy { pendingObservation = true }
    }

    public func processDisplayChange() async -> Bool { await run(.observe) }
    public func captureCurrentScreenConfiguration() async -> Bool { await run(.capture) }
    public func applySavedScreenConfiguration() async -> Bool { await run(.restore) }
    public func swapDisplayAssignments(firstRuntimeID: String, secondRuntimeID: String) async -> Bool {
        await run(.swap(firstRuntimeID, secondRuntimeID))
    }

    private func run(_ command: Command) async -> Bool {
        if busy {
            if case .observe = command { pendingObservation = true }
            else { DetectionLog(logger: logger).warn("operation_busy") }
            return false
        }
        busy = true
        defer { busy = false }
        var next = command
        var succeeded = false
        repeat {
            pendingObservation = false
            let log = DetectionLog(logger: logger)
            await sleepManager.sleep(milliseconds: delay)
            do { succeeded = try await execute(next, log: log) || succeeded }
            catch {
                succeeded = false
                log.error("operation_failed", ["error": String(describing: error), "action": "leave_saved_data_unchanged"])
                // Read failures and partial observations must not appear as a valid cached class.
                state = DisplaySetState()
            }
            next = .observe
        } while pendingObservation
        return succeeded
    }

    private func execute(_ command: Command, log: DetectionLog) async throws -> Bool {
        let displays = try displayManager.currentDisplays()
        log.observe(displays)
        if displays.isEmpty {
            lastObserved = nil; sessionMapping = [:]; state = DisplaySetState()
            log.info("no_displays", ["action": "leave_unchanged"])
            return false
        }
        try ScreenConfigurationLogic.validate(displays)
        guard let classID = DisplaySetClassID.from(displays) else { throw DisplaySetError.operationFailed("unknown_model") }
        var database = try displaySetStore.loadDatabase()
        try JSONDisplaySetStore.validate(database)
        let sameConnections = !connectionInvalidated && (lastObserved.map { ScreenConfigurationLogic.sameConnections($0, displays) } ?? false)
        connectionInvalidated = false
        if !sameConnections { sessionMapping = [:] }
        log.info("class_detection", ["class_id": classID.description])
        if case .observe = command, sameConnections, let lastObserved, Set(lastObserved) == Set(displays),
           let displaySetClass = database.classes.first(where: { $0.classID == classID }) {
            state = DisplaySetPresentation.make(displays, displaySetClass: displaySetClass, mapping: sessionMapping,
                                             lastProcessedAt: state.lastProcessedAt)
            log.info("unchanged_observation")
            return false
        }
        var displaySetClass: DisplaySetClass
        var mapping: [String: Int]
        if let existing = database.classes.first(where: { $0.classID == classID }) {
            displaySetClass = existing
            let assignmentResult = try SlotAssignmentResolver.resolve(displays: displays, displaySetClass: displaySetClass,
                                                     session: sameConnections ? sessionMapping : nil)
            mapping = assignmentResult.mapping
            log.assignment(assignmentResult)
            log.info("known_class")
        } else {
            let candidates = database.legacyProfiles.compactMap { LegacyProfileMigration.convert($0, displays: displays) }
            if candidates.count == 1, let candidate = candidates.first {
                displaySetClass = candidate.0; mapping = candidate.1
                log.info("legacy_live_mapping", ["originals": "preserved"])
            } else {
                if !database.legacyProfiles.isEmpty {
                    log.warn(candidates.isEmpty ? "legacy_unresolved" : "legacy_conflict", ["originals": "preserved"])
                }
                mapping = SlotAssignmentResolver.initialSlotAssignments(displays)
                displaySetClass = DisplaySetClass(configuration: try ScreenConfigurationLogic.capture(displays, mapping: mapping), updatedAt: now())
                log.info("new_class_capture")
                try persist(&displaySetClass, displays: displays, mapping: mapping, database: &database, log: log)
                complete(displays, displaySetClass: displaySetClass, mapping: mapping)
                return true
            }
        }

        var capture = false
        switch command {
        case .capture: capture = true
        case .observe: capture = sameConnections
        case .restore: break
        case .swap(let first, let second):
            guard first != second,
                  let a = displays.first(where: { $0.runtimeID == first }),
                  let b = displays.first(where: { $0.runtimeID == second }),
                  a.modelID == b.modelID, let firstSlot = mapping[first], let secondSlot = mapping[second] else {
                throw DisplaySetError.operationFailed("invalid_swap_pair")
            }
            let currentPlan = try ScreenConfigurationLogic.plan(displays, configuration: displaySetClass.configuration, mapping: mapping)
            guard ScreenConfigurationLogic.matches(displays, plan: currentPlan) else {
                throw DisplaySetError.operationFailed("swap_requires_current_configuration")
            }
            mapping[first] = secondSlot; mapping[second] = firstSlot
            log.info("instance_swap", ["first_runtime_id": first, "second_runtime_id": second])
        }
        log.debug("command_decision", ["command": commandName(command), "same_connections": String(sameConnections),
                                      "capture": String(capture)])

        if capture {
            if let permutation = try ScreenConfigurationLogic.permutation(displays, of: displaySetClass.configuration) {
                mapping = permutation
                log.info("instance_permutation", ["class_configuration": "unchanged"])
            } else {
                displaySetClass.configuration = try ScreenConfigurationLogic.capture(displays, mapping: mapping)
                displaySetClass.updatedAt = now()
                log.info("class_configuration_updated", ["origin": "external_or_unknown"])
            }
            try persist(&displaySetClass, displays: displays, mapping: mapping, database: &database, log: log)
            complete(displays, displaySetClass: displaySetClass, mapping: mapping)
            return true
        }

        let plan = try ScreenConfigurationLogic.plan(displays, configuration: displaySetClass.configuration, mapping: mapping)
        var observed = displays
        if !ScreenConfigurationLogic.matches(displays, plan: plan) {
            for target in plan.targets {
                var fields = ["runtime_id": target.runtimeID,
                              "origin": "\(target.targetFrame.origin.x),\(target.targetFrame.origin.y)",
                              "logical": "\(target.targetFrame.size.width)x\(target.targetFrame.size.height)",
                              "pixel": "\(target.targetMode.pixelSize.width)x\(target.targetMode.pixelSize.height)",
                              "is_main": String(target.isMain)]
                if let slot = mapping[target.runtimeID] { fields["slot_id"] = String(slot) }
                log.debug("apply_target", fields)
            }
            log.info("apply_started", ["display_count": String(plan.targets.count)])
            do {
                try displayManager.apply(plan: plan)
                await sleepManager.sleep(milliseconds: delay)
                observed = try displayManager.currentDisplays()
                log.observe(observed)
                // Own callbacks for this observed outcome are not external configuration edits.
                lastObserved = observed
                guard !connectionInvalidated else { throw DisplaySetError.operationFailed("apply_result_mismatch") }
                guard ScreenConfigurationLogic.matches(observed, plan: plan) else {
                    for display in observed {
                        guard let target = plan.targets.first(where: { $0.runtimeID == display.runtimeID }),
                              target.targetFrame != display.frame || target.targetMode != display.mode
                                  || target.isMain != display.isMain else { continue }
                        log.debug("verify_mismatch", [
                            "runtime_id": display.runtimeID,
                            "observed_origin": "\(display.frame.origin.x),\(display.frame.origin.y)",
                            "target_origin": "\(target.targetFrame.origin.x),\(target.targetFrame.origin.y)",
                            "observed_logical": "\(display.mode.logicalSize.width)x\(display.mode.logicalSize.height)",
                            "target_logical": "\(target.targetFrame.size.width)x\(target.targetFrame.size.height)",
                            "observed_pixel": "\(display.mode.pixelSize.width)x\(display.mode.pixelSize.height)",
                            "target_pixel": "\(target.targetMode.pixelSize.width)x\(target.targetMode.pixelSize.height)",
                            "observed_main": String(display.isMain), "target_main": String(target.isMain)
                        ])
                    }
                    throw DisplaySetError.operationFailed("apply_result_mismatch")
                }
            } catch {
                if let current = try? displayManager.currentDisplays() { lastObserved = current }
                throw error
            }
        } else { log.info("already_matches") }
        sessionMapping = mapping
        lastObserved = observed
        try persist(&displaySetClass, displays: observed, mapping: mapping, database: &database, log: log)
        complete(observed, displaySetClass: displaySetClass, mapping: mapping)
        log.info("configuration_applied", ["verified": "true"])
        return true
    }

    private func persist(_ displaySetClass: inout DisplaySetClass, displays: [DisplaySnapshot], mapping: [String: Int],
                         database: inout DisplaySetDatabase, log: DetectionLog) throws {
        let instance = ScreenConfigurationLogic.instance(displays, mapping: mapping, now: now())
        if let instance {
            displaySetClass.record(instance)
            log.info("instance_identified", ["persistent_identity": "true"])
        } else {
            displaySetClass.lastUsedAt = now()
            log.warn("session_only_identity", ["persistent_identity": "false"])
        }
        database.classes.removeAll { $0.classID == displaySetClass.classID }
        database.classes.append(displaySetClass)
        do { try displaySetStore.saveDatabase(database) }
        catch {
            // Keep an in-session mapping for a successful hardware change, but never claim a save.
            lastObserved = displays; sessionMapping = mapping
            log.error("display_set_database_save_failed", ["error": String(describing: error)])
            throw error
        }
        log.info("display_set_database_saved")
        if instance != nil { log.info("instance_saved") }
    }

    private func complete(_ displays: [DisplaySnapshot], displaySetClass: DisplaySetClass, mapping: [String: Int]) {
        lastObserved = displays; sessionMapping = mapping
        state = DisplaySetPresentation.make(displays, displaySetClass: displaySetClass, mapping: mapping, lastProcessedAt: now())
    }
}
