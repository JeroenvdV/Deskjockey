import AppKit
import DeskjockeyCore

/// Owns the menu bar UI and orchestrates display change handling.
///
/// Uses two layers of event coalescing:
/// 1. Debouncer (0.8s) -- batches rapid CGDisplayReconfigurationCallback bursts
/// 2. Coordinator delay (1s) -- waits for macOS to finalize display state
///
/// Tracks topology fingerprints to distinguish real hardware changes from
/// macOS firing extra reconfig events for the same set of displays.
@MainActor
final class AppDelegate: NSObject {
    private let displayManager = MacDisplayManager()
    private let sleepManager = TaskSleepManager()
    private let logger: Logger = FileLogger()
    private let loginItemManager = LoginItemManager()

    private var coordinator: DisplayConfigurationCoordinator?
    private var displayObserver: DisplayChangeObserver?
    private var debouncer = Debouncer(delay: 0.8)

    /// Guards against re-capturing a profile while we're in the middle of applying one.
    /// Without this, the intermediate (partially applied) state would overwrite the
    /// saved profile.
    private var isApplyingProfile = false

    /// Used to detect whether a display change is a real topology change (monitors
    /// added/removed) vs. macOS just adjusting the existing arrangement.
    private var lastTopologyFingerprint: DisplayTopologyFingerprint?

    /// Active apply task -- tracked so we can cancel it if a new topology
    /// change arrives before the previous apply completes.
    private var activeApplyTask: Task<Void, Never>?

    private var statusItem: NSStatusItem?
    private var launchAtLoginMenuItem: NSMenuItem?

    func start() {
        let store = JSONProfileStore(fileURL: profileFileURL())
        coordinator = DisplayConfigurationCoordinator(
            displayManager: displayManager,
            profileStore: store,
            logger: logger,
            sleepManager: sleepManager,
            reapplyDelayMilliseconds: 1_000
        )

        configureStatusItem()
        refreshMenu()

        let currentDisplays = displayManager.currentDisplays()
        guard !currentDisplays.isEmpty else {
            logger.info("No displays at launch")
            return
        }

        lastTopologyFingerprint = DisplayTopologyFingerprint.from(displays: currentDisplays)

        // On launch: apply saved profile if one exists for this monitor set,
        // otherwise capture the current arrangement as a new profile.
        if coordinator?.hasSavedProfile() == true {
            logger.info("Saved profile found at launch, applying")
            isApplyingProfile = true
            activeApplyTask = Task {
                await coordinator?.monitorSetDidChange()
                isApplyingProfile = false
                lastTopologyFingerprint = DisplayTopologyFingerprint.from(
                    displays: displayManager.currentDisplays()
                )
                refreshMenu()
            }
        } else {
            logger.info("No saved profile at launch, capturing current setup")
            do {
                try coordinator?.captureCurrentSetup()
                refreshMenu()
            } catch {
                logger.error("Failed to capture initial setup: \(error)")
            }
        }

        displayObserver = DisplayChangeObserver { [weak self] in
            self?.handleDisplayChange()
        }
    }

    // MARK: - Menu

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item

        if let button = item.button {
            let image = NSImage(
                systemSymbolName: "display.2",
                accessibilityDescription: "Deskjockey"
            )
            button.image = image
        }

        item.menu = NSMenu()
    }

    /// Rebuilds the entire menu from scratch. Called after every state change
    /// rather than trying to update individual items, since the display count
    /// and status can change.
    private func refreshMenu() {
        guard let menu = statusItem?.menu else { return }
        menu.removeAllItems()

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let versionItem = NSMenuItem(title: "Deskjockey v\(version)", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)
        menu.addItem(.separator())

        let summaries = coordinator?.displaySummaries() ?? []
        let allMatch = coordinator?.currentSetupMatchesSaved() ?? false
        let hasSaved = coordinator?.hasSavedProfile() ?? false

        // Profile status header
        let statusTitle: String
        if !hasSaved {
            statusTitle = "No Saved Profile"
        } else if allMatch {
            statusTitle = "Profile: In Sync"
        } else {
            statusTitle = "Profile: Out of Sync"
        }
        let statusItem = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)

        // Per-display status: checkmark = matches saved, dash = differs
        if !summaries.isEmpty {
            menu.addItem(.separator())
            let headerItem = NSMenuItem(
                title: "Displays (\(summaries.count))",
                action: nil,
                keyEquivalent: ""
            )
            headerItem.isEnabled = false
            menu.addItem(headerItem)

            for summary in summaries {
                let prefix: String
                if !hasSaved {
                    prefix = "  "
                } else if summary.matchesSaved {
                    prefix = "  "
                } else {
                    prefix = "  ~ "
                }
                let res = "\(summary.resolution.width)x\(summary.resolution.height)"
                let label = summary.isBuiltIn ? "\(summary.modelName) (built-in)" : summary.modelName
                let item = NSMenuItem(title: "\(prefix)\(label)  \(res)", action: nil, keyEquivalent: "")
                item.isEnabled = false
                if hasSaved {
                    item.state = summary.matchesSaved ? .on : .mixed
                }
                menu.addItem(item)
            }
        }

        // Actions
        menu.addItem(.separator())
        let saveItem = NSMenuItem(
            title: "Save Current Setup",
            action: #selector(saveCurrentSetup),
            keyEquivalent: "s"
        )
        saveItem.target = self
        menu.addItem(saveItem)

        let reapplyItem = NSMenuItem(
            title: "Re-apply Saved Setup",
            action: #selector(reapplySavedSetup),
            keyEquivalent: "r"
        )
        reapplyItem.target = self
        reapplyItem.isEnabled = hasSaved
        menu.addItem(reapplyItem)

        // Settings
        menu.addItem(.separator())
        let launchItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchItem.target = self
        launchItem.state = loginItemManager.isEnabled ? .on : .off
        launchAtLoginMenuItem = launchItem
        menu.addItem(launchItem)

        menu.addItem(.separator())
        let quitItem = NSMenuItem(
            title: "Quit Deskjockey",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        // Orange tint only when a saved profile exists but doesn't match.
        // No saved profile = neutral (not an error state).
        updateStatusIcon(inSync: !hasSaved || allMatch)
    }

    private func updateStatusIcon(inSync: Bool) {
        guard let button = statusItem?.button else { return }
        if inSync {
            button.contentTintColor = nil
        } else {
            button.contentTintColor = .systemOrange
        }
    }

    /// Programmatically opens the status item menu (e.g. when the app is relaunched).
    func showMenu() {
        guard let button = statusItem?.button else { return }
        button.performClick(nil)
    }

    // MARK: - Display change handling

    private func handleDisplayChange() {
        debouncer.schedule { [weak self] in
            self?.processDisplayChange()
        }
    }

    /// Core display change logic. Two branches:
    /// - Topology unchanged: macOS adjusted something (e.g. resolution scaling)
    ///   but the same monitors are connected. Capture the updated arrangement.
    /// - Topology changed: monitors were added or removed. Look up and apply
    ///   the saved profile for the new monitor set.
    private func processDisplayChange() {
        guard let coordinator else { return }
        let liveDisplays = displayManager.currentDisplays()
        let topology = DisplayTopologyFingerprint.from(displays: liveDisplays)

        if let lastTopologyFingerprint, lastTopologyFingerprint == topology {
            // Same monitors, but macOS changed something (e.g. user rearranged
            // in System Settings). Update the saved profile to match.
            if !isApplyingProfile {
                logger.info("Configuration updated by OS")
                do {
                    try coordinator.captureCurrentSetup()
                } catch {
                    logger.error("Failed to capture setup: \(error)")
                }
                refreshMenu()
            }
            return
        }

        // Different topology: monitors were plugged/unplugged.
        // Cancel any in-flight apply before starting a new one.
        activeApplyTask?.cancel()
        lastTopologyFingerprint = topology
        isApplyingProfile = true
        logger.info("Topology changed, reapplying profile")
        activeApplyTask = Task {
            await coordinator.monitorSetDidChange()
            isApplyingProfile = false
            lastTopologyFingerprint = DisplayTopologyFingerprint.from(
                displays: displayManager.currentDisplays()
            )
            refreshMenu()
        }
    }

    // MARK: - Actions

    @objc
    private func saveCurrentSetup() {
        do {
            try coordinator?.captureCurrentSetup()
            refreshMenu()
            logger.info("User saved current setup")
        } catch {
            logger.error("Failed to save setup: \(error)")
        }
    }

    @objc
    private func reapplySavedSetup() {
        guard let coordinator else { return }
        activeApplyTask?.cancel()
        isApplyingProfile = true
        logger.info("User requested reapply")
        activeApplyTask = Task {
            await coordinator.monitorSetDidChange()
            isApplyingProfile = false
            refreshMenu()
        }
    }

    @objc
    private func toggleLaunchAtLogin() {
        let shouldEnable = launchAtLoginMenuItem?.state != .on
        do {
            try loginItemManager.setEnabled(shouldEnable)
            launchAtLoginMenuItem?.state = shouldEnable ? .on : .off
        } catch {
            logger.error("Failed to change launch-at-login state: \(error)")
            launchAtLoginMenuItem?.state = loginItemManager.isEnabled ? .on : .off
        }
    }

    @objc
    private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Helpers

    private func profileFileURL() -> URL {
        let supportRoot = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSHomeDirectory())
        return supportRoot
            .appendingPathComponent("Deskjockey", isDirectory: true)
            .appendingPathComponent("profiles.json", isDirectory: false)
    }
}
