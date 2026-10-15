import AppKit
import CoreGraphics
import DeskjockeyCore

/// Presents coordinator state and forwards display events and user commands.
/// The coordinator owns detection, capture, and configuration transactions.
@MainActor
final class AppDelegate: NSObject {
    private lazy var displayManager = MacDisplayManager(logger: logger)
    private let sleepManager = TaskSleepManager()
    private let logger: Logger = FileLogger()
    private let loginItemManager = LoginItemManager()

    private var coordinator: ScreenConfigurationCoordinator?
    private var displayObserver: DisplayChangeObserver?
    private var debouncer = Debouncer(delay: 0.8)

    private var statusItem: NSStatusItem?
    private var launchAtLoginMenuItem: NSMenuItem?

    /// Timestamp of the last processed display change, persisted across launches.
    private var lastProcessedAt: Date?
    private static let lastProcessedKey = "lastProcessedAt"

    func start() {
        let store = JSONDisplaySetStore(fileURL: displaySetDatabaseURL())
        coordinator = ScreenConfigurationCoordinator(
            displayManager: displayManager,
            displaySetStore: store,
            logger: logger,
            sleepManager: sleepManager,
            reapplyDelayMilliseconds: 1_000
        )

        lastProcessedAt = UserDefaults.standard.object(forKey: Self.lastProcessedKey) as? Date
        configureStatusItem()
        refreshMenu()

        displayObserver = DisplayChangeObserver { [weak self] displayID, flags in
            self?.logger.info("event=display_callback runtime_id=\(displayID) flags=\(flags)")
            let changes = CGDisplayChangeSummaryFlags(rawValue: flags)
            let connectionFired = !changes.intersection([.addFlag, .removeFlag, .enabledFlag, .disabledFlag]).isEmpty
            self?.logger.debug("event=display_change_flags runtime_id=\(displayID) change_flags=\(changes.rawValue) connection_fired=\(connectionFired)")
            if connectionFired {
                self?.coordinator?.displayConnectionDidChange()
            }
            self?.handleDisplayChange()
        }
        processDisplayChange()
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
        item.menu?.autoenablesItems = false
        item.menu?.delegate = self
    }

    /// Rebuilds the entire menu from scratch. Called after every state change
    /// rather than trying to update individual items, since the display count
    /// and status can change.
    private func refreshMenu() {
        guard let menu = statusItem?.menu else { return }
        menu.removeAllItems()

        let summaries = coordinator?.state.summaries ?? []
        let allMatch = coordinator?.state.matchesScreenConfiguration ?? false
        let hasSaved = coordinator?.state.hasSavedScreenConfiguration ?? false

        // Combined display set class status + last-processed timestamp
        var statusTitle: String
        if !hasSaved {
            statusTitle = "No Saved Configuration"
        } else if allMatch {
            statusTitle = "In Sync"
        } else {
            statusTitle = "Out of Sync"
        }
        if let lastProcessed = lastProcessedAt {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            let timeAgo = formatter.localizedString(for: lastProcessed, relativeTo: Date())
            statusTitle += " \u{00b7} last change \(timeAgo)"
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
                } else if summary.matchesScreenConfiguration {
                    prefix = "  "
                } else {
                    prefix = "  ~ "
                }
                let res = "\(summary.pixelSize.width)x\(summary.pixelSize.height)"
                let label = summary.isBuiltIn ? "\(summary.displayName) (built-in)" : summary.displayName
                let item = NSMenuItem(title: "\(prefix)\(label)  \(res)", action: nil, keyEquivalent: "")
                item.isEnabled = false
                if hasSaved {
                    item.state = summary.matchesScreenConfiguration ? .on : .mixed
                }
                menu.addItem(item)
            }
        }

        if let candidates = coordinator?.state.swapCandidates, !candidates.isEmpty {
            menu.addItem(.separator())
            for candidate in candidates {
                let item = NSMenuItem(
                    title: candidates.count == 1 ? "Swap Identical Displays" : candidate.title,
                    action: #selector(swapDisplayAssignments(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = candidate
                item.isEnabled = hasSaved
                item.toolTip = "Exchange screen assignments without changing the shared configuration. Click again to undo."
                menu.addItem(item)
            }
        }

        // Manual operations submenu
        menu.addItem(.separator())
        let manualMenu = NSMenu()
        manualMenu.autoenablesItems = false
        let saveItem = NSMenuItem(
            title: "Save Current Configuration",
            action: #selector(captureCurrentScreenConfiguration),
            keyEquivalent: "s"
        )
        saveItem.target = self
        manualMenu.addItem(saveItem)

        let reapplyItem = NSMenuItem(
            title: "Apply Saved Configuration",
            action: #selector(applySavedScreenConfiguration),
            keyEquivalent: "r"
        )
        reapplyItem.target = self
        reapplyItem.isEnabled = hasSaved
        manualMenu.addItem(reapplyItem)

        let manualItem = NSMenuItem(title: "Manual Operations", action: nil, keyEquivalent: "")
        manualItem.submenu = manualMenu
        menu.addItem(manualItem)

        // Open config file
        menu.addItem(.separator())
        let openConfigItem = NSMenuItem(
            title: "Open Config File",
            action: #selector(openConfigFile),
            keyEquivalent: ""
        )
        openConfigItem.target = self
        menu.addItem(openConfigItem)

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
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let quitItem = NSMenuItem(
            title: "Quit Deskjockey v\(version)",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        // Orange tint only when a saved display set class exists but doesn't match.
        // No saved display set class = neutral (not an error state).
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

    private func processDisplayChange() {
        perform { await $0.processDisplayChange() }
    }

    /// The coordinator serializes operations and records failures without alerts.
    private func perform(_ operation: @escaping (ScreenConfigurationCoordinator) async -> Bool) {
        guard let coordinator else { return }
        Task { [weak self] in
            let succeeded = await operation(coordinator)
            guard let self else { return }
            if succeeded { recordProcessed() }
            refreshMenu()
            if succeeded { flashStatusIcon() }
        }
    }

    // MARK: - Actions

    @objc
    private func swapDisplayAssignments(_ sender: NSMenuItem) {
        guard let candidate = sender.representedObject as? DisplaySwapCandidate else { return }
        perform {
            await $0.swapDisplayAssignments(
                firstRuntimeID: candidate.firstRuntimeID,
                secondRuntimeID: candidate.secondRuntimeID
            )
        }
    }

    @objc
    private func captureCurrentScreenConfiguration() {
        perform { await $0.captureCurrentScreenConfiguration() }
    }

    @objc
    private func applySavedScreenConfiguration() {
        perform { await $0.applySavedScreenConfiguration() }
    }

    @objc
    private func openConfigFile() {
        let url = displaySetDatabaseURL()
        logger.info("Opening config file at: \(url.path)")
        NSWorkspace.shared.open(url)
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

    // MARK: - Visual feedback

    /// Briefly flashes the menu bar icon green to confirm a display change was processed.
    private func flashStatusIcon() {
        guard let button = statusItem?.button else { return }
        button.contentTintColor = .systemGreen
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            let allMatch = self?.coordinator?.state.matchesScreenConfiguration ?? false
            let hasSaved = self?.coordinator?.state.hasSavedScreenConfiguration ?? false
            self?.updateStatusIcon(inSync: !hasSaved || allMatch)
        }
    }

    /// Records the current time as the last-processed timestamp and persists it.
    private func recordProcessed() {
        lastProcessedAt = Date()
        UserDefaults.standard.set(lastProcessedAt, forKey: Self.lastProcessedKey)
    }

    // MARK: - Helpers

    private func displaySetDatabaseURL() -> URL {
        let supportRoot = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSHomeDirectory())
        return supportRoot
            .appendingPathComponent("Deskjockey", isDirectory: true)
            .appendingPathComponent("profiles.json", isDirectory: false)
    }
}

// MARK: - NSMenuDelegate

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        refreshMenu()
    }
}
