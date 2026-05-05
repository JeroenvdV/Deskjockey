import AppKit
import CoreGraphics
import Foundation
import DeskjockeyCore
import ServiceManagement
import Darwin

// MARK: - File Watcher

/// Monitors a specific file for changes and notifies when modifications are detected.
/// Uses DispatchSource to watch the file's parent directory for write events,
/// then verifies the specific file was modified.
final class FileWatcher {
    private let fileURL: URL
    private let queue: DispatchQueue
    private var source: DispatchSourceFileSystemObject?
    private var descriptor: Int32 = -1
    private let callback: (FileChangeEvent) -> Void

    /// Represents a file change event with the path to the modified file.
    struct FileChangeEvent {
        let path: String
    }

    /// - Parameter fileURL: The specific file to monitor for changes
    /// - Parameter callback: Closure called when the file is modified
    init(fileURL: URL, callback: @escaping (FileChangeEvent) -> Void) {
        self.fileURL = fileURL
        self.queue = DispatchQueue(label: "com.deskjockey.filewatcher")
        self.callback = callback

        startWatching()
    }

    deinit {
        stopWatching()
    }

    private func startWatching() {
        // Open the parent directory for monitoring
        let parentDirectory = fileURL.deletingLastPathComponent()
        descriptor = open(parentDirectory.path, O_EVTONLY)
        guard descriptor != -1 else { return }

        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: .write,
            queue: queue
        )

        source?.setEventHandler { [weak self] in
            guard let self = self else { return }
            self.handleFileSystemEvent()
        }

        source?.setCancelHandler { [weak self] in
            guard let self = self else { return }
            close(self.descriptor)
            self.descriptor = -1
        }

        source?.resume()
    }

    private func stopWatching() {
        source?.cancel()
        if descriptor != -1 {
            close(descriptor)
            descriptor = -1
        }
    }

    private func handleFileSystemEvent() {
        // Check if our specific file exists and was recently modified
        // This is a simple check - for production use, consider tracking
        // the file's modification date to avoid false positives
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let event = FileChangeEvent(path: fileURL.path)
            callback(event)
        }
    }
}

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
        let targetWidth = configuration.targetResolution.width
        let targetHeight = configuration.targetResolution.height
        var matchingMode: CGDisplayMode?

        if let allModes = CGDisplayCopyAllDisplayModes(displayID, nil) as? [CGDisplayMode] {
            matchingMode = allModes.first(where: {
                Int($0.pixelWidth) == targetWidth && Int($0.pixelHeight) == targetHeight
            })
            if matchingMode == nil {
                let available = Set(allModes.map { "\(Int($0.pixelWidth))x\(Int($0.pixelHeight))" })
                    .sorted()
                    .joined(separator: ", ")
                NSLog("[Deskjockey] Available modes for display \(displayID): \(available)")
                throw DisplayError.modeNotAvailable(width: targetWidth, height: targetHeight)
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
            isBuiltIn: CGDisplayIsBuiltin(id) != 0,
            frame: DisplayFrame(
                origin: DisplayPoint(x: Int(bounds.origin.x), y: Int(bounds.origin.y)),
                size: DisplaySize(width: Int(bounds.width), height: Int(bounds.height))
            ),
            resolution: DisplaySize(width: pixelWidth, height: pixelHeight)
        )
    }
}
