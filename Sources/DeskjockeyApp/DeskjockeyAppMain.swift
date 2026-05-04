import AppKit

@main
final class DeskjockeyAppMain: NSObject, NSApplicationDelegate {
    private static let showMenuNotification = "ai.mistral.Deskjockey.showMenu"
    private var appDelegate: AppDelegate?

    /// File descriptor for the single-instance lock file.
    private static var lockFD: Int32 = -1

    static func main() {
        if !acquireLock() {
            // Another instance is running — tell it to show its menu and exit.
            DistributedNotificationCenter.default().postNotificationName(
                NSNotification.Name(showMenuNotification),
                object: nil
            )
            exit(0)
        }

        let app = NSApplication.shared
        let delegate = DeskjockeyAppMain()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    /// Try to acquire an exclusive lock on a known file. Returns true if
    /// this is the only running instance, false if another holds the lock.
    private static func acquireLock() -> Bool {
        let lockPath = "/tmp/ai.mistral.Deskjockey.lock"
        let fd = Darwin.open(lockPath, O_WRONLY | O_CREAT, 0o600)
        guard fd >= 0 else { return true } // Can't create lock file — proceed anyway.
        if flock(fd, LOCK_EX | LOCK_NB) == 0 {
            lockFD = fd // Keep fd open for the process lifetime.
            return true
        }
        Darwin.close(fd)
        return false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleShowMenu),
            name: NSNotification.Name(Self.showMenuNotification),
            object: nil
        )

        appDelegate = AppDelegate()
        appDelegate?.start()
    }

    @objc private func handleShowMenu(_ notification: Notification) {
        Task { @MainActor in
            appDelegate?.showMenu()
        }
    }
}
