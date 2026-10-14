import AppKit
import CoreGraphics
import Foundation
import DeskjockeyCore
import ServiceManagement

/// Registers for CGDisplayReconfigurationCallback and forwards events to the main queue.
/// The callback fires for every display change (resolution, arrangement, plug/unplug),
/// often multiple times per physical event -- the Debouncer in AppDelegate coalesces these.
final class DisplayChangeObserver {
    private let callback: () -> Void
    private var observerToken: UnsafeMutableRawPointer?

    private static let cgCallback: CGDisplayReconfigurationCallBack = { _, _, userInfo in
        guard let userInfo else { return }
        let observer = Unmanaged<DisplayChangeObserver>
            .fromOpaque(userInfo)
            .takeUnretainedValue()
        DispatchQueue.main.async {
            observer.callback()
        }
    }

    // passUnretained is safe here: the observer is stored in AppDelegate which
    // lives for the entire app lifetime, so the pointer cannot dangle while the
    // callback is registered.  deinit removes the callback at app termination.
    init(callback: @escaping () -> Void) {
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

final class MacDisplayManager: DisplayManaging {
    func currentDisplays() -> [DisplaySnapshot] {
        NSScreen.screens.compactMap { screen -> DisplaySnapshot? in
            guard let screenNumber = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? NSNumber else {
                return nil
            }
            return snapshotForScreen(screen, displayID: screenNumber.uint32Value)
        }
    }

    func apply(configuration: DisplayConfiguration, to display: DisplaySnapshot) throws {
        guard let displayID = UInt32(configuration.runtimeID) else {
            throw DisplayError.displayNotFound(runtimeID: configuration.runtimeID)
        }

        // Resolve the target display mode before starting the CG transaction
        // so we can apply origin + mode atomically in a single commit.
        // If no mode matches, the origin is still applied and the error is thrown after.
        var matchingMode: CGDisplayMode?
        var modeError: DisplayError?
        if let current = CGDisplayCopyDisplayMode(displayID), Self.mode(current, matches: configuration) {
            matchingMode = nil
        } else {
            let allModes = Self.allModes(of: displayID)
            let candidates = allModes.filter { Self.mode($0, matches: configuration) }
            let usable = candidates.filter { $0.isUsableForDesktopGUI() }
            matchingMode = (usable.isEmpty ? candidates : usable).max { $0.refreshRate < $1.refreshRate }
            if matchingMode == nil {
                let available = Set(allModes.map {
                    "\($0.width)x\($0.height)@\($0.pixelWidth)x\($0.pixelHeight)"
                })
                    .sorted()
                    .joined(separator: ", ")
                NSLog("[Deskjockey] Available modes for display \(displayID): \(available)")
                modeError = DisplayError.modeNotAvailable(
                    width: configuration.targetResolution.width,
                    height: configuration.targetResolution.height
                )
            }
        }

        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else {
            throw DisplayError.configurationFailed("Could not begin display configuration")
        }

        let originResult = CGConfigureDisplayOrigin(
            config,
            displayID,
            Int32(configuration.targetFrame.origin.x),
            Int32(configuration.targetFrame.origin.y)
        )
        if originResult != .success {
            CGCancelDisplayConfiguration(config)
            throw DisplayError.configurationFailed(
                "Failed to set origin for display \(displayID)"
            )
        }

        if let mode = matchingMode {
            CGConfigureDisplayWithDisplayMode(config, displayID, mode, nil)
        }

        let completeResult = CGCompleteDisplayConfiguration(config, .permanently)
        if completeResult != .success {
            throw DisplayError.configurationFailed(
                "Failed to commit configuration for display \(displayID)"
            )
        }
        if let modeError {
            throw modeError
        }
    }

    func moveDisplays(to origins: [String: DisplayPoint]) throws {
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else {
            throw DisplayError.configurationFailed("Could not begin display configuration")
        }
        for (runtimeID, origin) in origins {
            guard let displayID = UInt32(runtimeID),
                  CGConfigureDisplayOrigin(config, displayID, Int32(origin.x), Int32(origin.y)) == .success
            else {
                CGCancelDisplayConfiguration(config)
                throw DisplayError.configurationFailed("Failed to set origin for display \(runtimeID)")
            }
        }
        if CGCompleteDisplayConfiguration(config, .permanently) != .success {
            throw DisplayError.configurationFailed("Failed to commit display origins")
        }
    }

    /// Returns all modes of a display, including scaled HiDPI modes.
    /// Without the option, macOS hides the HiDPI modes that System Settings offers as "Larger Text" / "More Space".
    private static func allModes(of displayID: CGDirectDisplayID) -> [CGDisplayMode] {
        let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        return CGDisplayCopyAllDisplayModes(displayID, options) as? [CGDisplayMode] ?? []
    }

    /// Returns true if the mode has the target size in both points and pixels.
    /// Pixels alone are ambiguous: 1920x1080 HiDPI and 3840x2160 both use 3840x2160 pixels.
    private static func mode(_ mode: CGDisplayMode, matches configuration: DisplayConfiguration) -> Bool {
        mode.width == configuration.targetFrame.size.width
            && mode.height == configuration.targetFrame.size.height
            && mode.pixelWidth == configuration.targetResolution.width
            && mode.pixelHeight == configuration.targetResolution.height
    }

    private func snapshotForScreen(
        _ screen: NSScreen,
        displayID id: CGDirectDisplayID
    ) -> DisplaySnapshot {
        let bounds = CGDisplayBounds(id)
        let mode = CGDisplayCopyDisplayMode(id)
        let pixelWidth = mode?.pixelWidth ?? Int(bounds.width)
        let pixelHeight = mode?.pixelHeight ?? Int(bounds.height)

        return DisplaySnapshot(
            runtimeID: String(id),
            modelName: screen.localizedName,
            serialNumber: CGDisplaySerialNumber(id),
            portIdentifier: CGDisplayUnitNumber(id),
            isBuiltIn: CGDisplayIsBuiltin(id) != 0,
            frame: DisplayFrame(
                origin: DisplayPoint(x: Int(bounds.origin.x), y: Int(bounds.origin.y)),
                size: DisplaySize(width: Int(bounds.width), height: Int(bounds.height))
            ),
            resolution: DisplaySize(width: pixelWidth, height: pixelHeight)
        )
    }
}
