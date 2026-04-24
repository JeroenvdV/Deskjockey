import AppKit

@main
final class DeskjockeyAppMain: NSObject, NSApplicationDelegate {
    private var appDelegate: AppDelegate?

    static func main() {
        let app = NSApplication.shared
        let delegate = DeskjockeyAppMain()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        appDelegate = AppDelegate()
        appDelegate?.start()
    }
}
