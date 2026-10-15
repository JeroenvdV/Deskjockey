import AppKit
import CoreGraphics
import Foundation
import IOKit.graphics
import DeskjockeyCore
import ServiceManagement

/// Registers for CGDisplayReconfigurationCallback and forwards events to the main queue.
/// The callback fires for every display change (resolution, arrangement, plug/unplug),
/// often multiple times per physical event -- the Debouncer in AppDelegate coalesces these.
final class DisplayChangeObserver {
    private let callback: (UInt32, UInt32) -> Void
    private var observerToken: UnsafeMutableRawPointer?

    private static let cgCallback: CGDisplayReconfigurationCallBack = { displayID, flags, userInfo in
        guard let userInfo else { return }
        let observer = Unmanaged<DisplayChangeObserver>
            .fromOpaque(userInfo)
            .takeUnretainedValue()
        DispatchQueue.main.async {
            observer.callback(displayID, flags.rawValue)
        }
    }

    // passUnretained is safe here: the observer is stored in AppDelegate which
    // lives for the entire app lifetime, so the pointer cannot dangle while the
    // callback is registered.  deinit removes the callback at app termination.
    init(callback: @escaping (UInt32, UInt32) -> Void) {
        self.callback = callback
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        self.observerToken = pointer
        CGDisplayRegisterReconfigurationCallback(Self.cgCallback, pointer)
    }

    deinit {
        CGDisplayRemoveReconfigurationCallback(Self.cgCallback, observerToken)
    }
}

enum LoginItemError: Error {
    case unsupported
}

final class LoginItemManager {
    var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    func setEnabled(_ enabled: Bool) throws {
        if #available(macOS 13.0, *) {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return
        }
        throw LoginItemError.unsupported
    }
}

@MainActor
final class MacDisplayManager: DisplayManaging {
    let logger: Logger

    init(logger: Logger = NullLogger()) {
        self.logger = logger
    }

    func currentDisplays() throws -> [DisplaySnapshot] {
        let ids = try participatingDisplayIDs()
        if ids.isEmpty { return [] }
        var names: [CGDirectDisplayID: String] = [:]
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                  let id = UInt32(exactly: number.int64Value), id != 0,
                  ids.contains(id), names[id] == nil else {
                throw failure("invalid_inventory", "NSScreen has a missing, duplicate, or offline runtime ID")
            }
            names[id] = screen.localizedName
        }
        let displays = try ids.map { try snapshot(displayID: $0, name: names[$0]) }
        guard displays.filter(\.isMain).count == 1,
              displays.first(where: \.isMain)?.frame.origin == DisplayPoint(x: 0, y: 0),
              try participatingDisplayIDs() == ids else {
            throw failure("unstable_inventory", "The display set or main display changed during observation")
        }
        // A second read detects mode, identity, and geometry changes within this inventory.
        let confirmed = try ids.map { try snapshot(displayID: $0, name: names[$0]) }
        guard confirmed == displays else {
            throw failure("unstable_inventory", "Display state changed during observation")
        }
        return displays
    }

    func apply(plan: DisplayApplyPlan) throws {
        let live = try currentDisplays()
        let observedIDs = plan.observedDisplays.map(\.runtimeID)
        let targetIDs = plan.targets.map(\.runtimeID)
        guard !targetIDs.isEmpty,
              Set(observedIDs).count == observedIDs.count,
              Set(targetIDs).count == targetIDs.count,
              Set(targetIDs) == Set(observedIDs),
              Set(targetIDs) == Set(live.map(\.runtimeID)) else {
            throw failure("invalid_plan", "A plan must include every display exactly once")
        }
        guard Set(live) == Set(plan.observedDisplays) else {
            throw failure("stale_plan", "The observed display snapshot is no longer current")
        }
        guard !live.contains(where: \.isMirrored) else {
            throw failure("mirror_mode_unsupported", "Origin or mode changes can alter a mirror set")
        }
        guard live.allSatisfy({ $0.modelID != nil && $0.identityIssue == nil }) else {
            throw failure("invalid_identity", "A display has no reliable hardware model identity")
        }
        guard plan.targets.filter(\.isMain).count == 1 else {
            throw failure("invalid_main", "A plan must select exactly one main display")
        }

        var prepared: [(id: CGDirectDisplayID, x: Int32, y: Int32, mode: CGDisplayMode?)] = []
        for target in plan.targets {
            guard let id = UInt32(target.runtimeID), id != 0,
                  String(id) == target.runtimeID else {
                throw DisplaySetError.displayNotFound(runtimeID: target.runtimeID)
            }
            try validate(frame: target.targetFrame, mode: target.targetMode, runtimeID: target.runtimeID)
            let origin = target.targetFrame.origin
            guard target.isMain == (origin.x == 0 && origin.y == 0) else {
                throw failure("invalid_main", "Only the main display may have origin (0, 0)")
            }
            guard let current = CGDisplayCopyDisplayMode(id) else {
                throw failure("mode_unavailable", "runtime_id=\(id) current mode is unavailable")
            }
            let selected = try selectMode(for: id, target: target.targetMode, current: current)
            prepared.append((id, Int32(origin.x), Int32(origin.y), selected))
        }
        // Mode discovery can take time. Revalidate before opening the transaction.
        guard Set(try currentDisplays()) == Set(plan.observedDisplays) else {
            throw failure("stale_plan", "Display state changed during preflight")
        }

        var transaction: CGDisplayConfigRef?
        let beginResult = CGBeginDisplayConfiguration(&transaction)
        guard beginResult == .success, let transaction else {
            throw failure("begin_failed", "cg_error=\(beginResult.rawValue)")
        }
        do {
            for target in prepared {
                if let mode = target.mode {
                    let result = CGConfigureDisplayWithDisplayMode(transaction, target.id, mode, nil)
                    guard result == .success else {
                        throw failure("mode_stage_failed", "runtime_id=\(target.id) cg_error=\(result.rawValue)")
                    }
                }
            }
            // Global coordinates use the main display's upper-left corner as origin.
            // Set every origin: Quartz otherwise relocates unspecified displays.
            for target in prepared {
                let result = CGConfigureDisplayOrigin(transaction, target.id, target.x, target.y)
                guard result == .success else {
                    throw failure("origin_stage_failed", "runtime_id=\(target.id) cg_error=\(result.rawValue)")
                }
            }
        } catch {
            let cancelResult = CGCancelDisplayConfiguration(transaction)
            guard cancelResult == .success else {
                throw failure("cancel_failed", "cg_error=\(cancelResult.rawValue) staging_error=\(error)")
            }
            throw error
        }
        // Complete invalidates the transaction even on failure. Do not cancel it afterward.
        // Quartz can adjust geometry; the coordinator must verify the observed result.
        let result = CGCompleteDisplayConfiguration(transaction, .permanently)
        guard result == .success else {
            throw failure("commit_failed", "cg_error=\(result.rawValue)")
        }
    }

    private func participatingDisplayIDs() throws -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        let countResult = CGGetOnlineDisplayList(0, nil, &count)
        guard countResult == .success else {
            throw failure("invalid_inventory", "CGGetOnlineDisplayList count=\(count) cg_error=\(countResult.rawValue)")
        }
        if count == 0 { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        var actualCount: UInt32 = 0
        let listResult = CGGetOnlineDisplayList(count, &ids, &actualCount)
        var confirmedCount: UInt32 = 0
        let confirmResult = CGGetOnlineDisplayList(0, nil, &confirmedCount)
        guard listResult == .success, confirmResult == .success,
              actualCount == count, confirmedCount == count,
              !ids.contains(0), Set(ids).count == ids.count else {
            throw failure("unstable_inventory", "Display enumeration was incomplete: list_error=\(listResult.rawValue) count_error=\(confirmResult.rawValue)")
        }
        // A sleeping or closed-lid panel can be online without participating in the desktop.
        // Include mirror members so the coordinator can reject the entire mirror configuration.
        return ids.filter { CGDisplayIsActive($0) != 0 || CGDisplayIsInMirrorSet($0) != 0 }.sorted()
    }

    private func snapshot(displayID id: CGDirectDisplayID, name: String?) throws -> DisplaySnapshot {
        let mirrored = CGDisplayIsInMirrorSet(id) != 0
        // Online hardware mirrors need not be drawable or have an NSScreen.
        // Keep them in the inventory so preflight cannot overlook a mirror member.
        guard CGDisplayIsOnline(id) != 0,
              mirrored || (CGDisplayIsActive(id) != 0 && name != nil) else {
            throw failure("invalid_inventory", "runtime_id=\(id) is inactive or has no NSScreen")
        }
        guard let currentMode = CGDisplayCopyDisplayMode(id) else {
            throw failure("mode_unavailable", "runtime_id=\(id) current mode is unavailable")
        }
        let bounds = CGDisplayBounds(id)
        guard let x = Int32(exactly: bounds.origin.x), let y = Int32(exactly: bounds.origin.y),
              let width = Int32(exactly: bounds.width), let height = Int32(exactly: bounds.height) else {
            throw failure("invalid_geometry", "runtime_id=\(id) has nonintegral or out-of-range bounds")
        }
        let frame = DisplayFrame(
            origin: DisplayPoint(x: Int(x), y: Int(y)),
            size: DisplaySize(width: Int(width), height: Int(height))
        )
        let mode = displayMode(currentMode)
        try validate(frame: frame, mode: mode, runtimeID: String(id))
        let vendor = CGDisplayVendorNumber(id)
        let product = CGDisplayModelNumber(id)
        let identified = vendor != 0 && vendor != UInt32(kDisplayVendorIDUnknown)
            && product != 0 && product != UInt32(kDisplayProductIDGeneric)
        return DisplaySnapshot(
            runtimeID: String(id),
            displayName: name ?? "Display \(id)",
            modelID: identified ? DisplayModelID(vendorID: vendor, productID: product) : nil,
            serialNumber: CGDisplaySerialNumber(id),
            logicalUnitNumber: CGDisplayUnitNumber(id),
            isBuiltIn: CGDisplayIsBuiltin(id) != 0,
            isMain: CGDisplayIsMain(id) != 0,
            isMirrored: mirrored,
            frame: frame,
            mode: mode,
            identityIssue: identified ? nil : "reason=unknown_model raw_vendor_id=\(vendor) raw_product_id=\(product)"
        )
    }

    private func validate(frame: DisplayFrame, mode: DisplayMode, runtimeID: String) throws {
        let sizes = [frame.size, mode.logicalSize, mode.pixelSize]
        guard sizes.allSatisfy({
            $0.width > 0 && $0.height > 0
                && Int32(exactly: $0.width) != nil && Int32(exactly: $0.height) != nil
        }), Int32(exactly: frame.origin.x) != nil, Int32(exactly: frame.origin.y) != nil,
              frame.size == mode.logicalSize else {
            throw failure("invalid_geometry", "runtime_id=\(runtimeID) invalid frame or logical/pixel mode dimensions")
        }
        guard Int32(exactly: Int64(frame.origin.x) + Int64(frame.size.width)) != nil,
              Int32(exactly: Int64(frame.origin.y) + Int64(frame.size.height)) != nil else {
            throw failure("invalid_geometry", "runtime_id=\(runtimeID) frame exceeds Int32 coordinates")
        }
    }

    private func displayMode(_ mode: CGDisplayMode) -> DisplayMode {
        DisplayMode(
            logicalSize: DisplaySize(width: mode.width, height: mode.height),
            pixelSize: DisplaySize(width: mode.pixelWidth, height: mode.pixelHeight)
        )
    }

    /// Nil means the current mode already has the requested dimensions.
    private func selectMode(
        for id: CGDirectDisplayID,
        target: DisplayMode,
        current: CGDisplayMode
    ) throws -> CGDisplayMode? {
        if displayMode(current) == target {
            logger.debug("event=mode_already_current runtime_id=\(id)")
            return nil
        }
        // Duplicate low-resolution modes are the only way to list scaled (HiDPI) modes.
        let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        guard let modes = CGDisplayCopyAllDisplayModes(id, options) as? [CGDisplayMode] else {
            throw failure("mode_unavailable", "runtime_id=\(id) could not enumerate modes")
        }
        logger.debug("event=mode_enumeration runtime_id=\(id) count=\(modes.count)")
        let compatible = modes.filter { displayMode($0) == target && $0.isUsableForDesktopGUI() }
        // Saved modes carry no refresh dimension; prefer the highest rate, all else equal.
        let ranked = compatible.sorted { lhs, rhs in
            if lhs.refreshRate != rhs.refreshRate { return lhs.refreshRate > rhs.refreshRate }
            let leftFlags = lhs.ioFlags == current.ioFlags
            let rightFlags = rhs.ioFlags == current.ioFlags
            if leftFlags != rightFlags { return leftFlags }
            return lhs.ioDisplayModeID < rhs.ioDisplayModeID
        }
        guard let selected = ranked.first else {
            logger.debug("event=mode_candidates_empty runtime_id=\(id) logical=\(target.logicalSize.width)x\(target.logicalSize.height) pixel=\(target.pixelSize.width)x\(target.pixelSize.height)")
            throw failure("mode_unavailable", "runtime_id=\(id) logical=\(target.logicalSize.width)x\(target.logicalSize.height) pixel=\(target.pixelSize.width)x\(target.pixelSize.height)")
        }
        logger.debug("event=mode_selected runtime_id=\(id) logical=\(selected.width)x\(selected.height) pixel=\(selected.pixelWidth)x\(selected.pixelHeight) refresh_rate=\(selected.refreshRate) candidates=\(compatible.count)")
        return selected
    }

    private func failure(_ reason: String, _ detail: String) -> DisplaySetError {
        .operationFailed("reason=\(reason) \(detail)")
    }
}
