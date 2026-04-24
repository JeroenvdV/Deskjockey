import Foundation

// MARK: - Protocols
// These protocols define the boundary between DeskjockeyCore (platform-independent)
// and DeskjockeyApp (macOS-specific). Each has a real implementation in Runtime.swift
// and a mock/no-op implementation for tests.

/// Reads the current display state and applies configuration changes.
public protocol DisplayManaging {
    func currentDisplays() -> [DisplaySnapshot]
    func apply(configuration: DisplayConfiguration, to display: DisplaySnapshot) throws
}

/// Shows/hides a temporary overlay during display reconfiguration to mask visual glitches.
public protocol OverlayManaging {
    func show(timeoutSeconds: TimeInterval)
    func hide()
}

public protocol Logger {
    func info(_ message: String)
    func warn(_ message: String)
    func error(_ message: String)
}

/// Silent logger for tests and contexts where logging is not needed.
public struct NullLogger: Logger {
    public init() {}
    public func info(_: String) {}
    public func warn(_: String) {}
    public func error(_: String) {}
}

// MARK: - File logger

/// Appends timestamped log lines to ~/Library/Logs/Deskjockey/deskjockey.log.
/// Thread-safe via a serial dispatch queue. Supports multi-line messages
/// (e.g. display inventory on topology change).
public final class FileLogger: Logger {
    private let fileHandle: FileHandle?
    private let dateFormatter: DateFormatter
    private let queue = DispatchQueue(label: "com.deskjockey.logger")

    public init(directory: URL? = nil) {
        let logDir = directory ?? FileLogger.defaultLogDirectory()
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        let logFile = logDir.appendingPathComponent("deskjockey.log")

        if !FileManager.default.fileExists(atPath: logFile.path) {
            FileManager.default.createFile(atPath: logFile.path, contents: nil)
        }

        fileHandle = try? FileHandle(forWritingTo: logFile)
        fileHandle?.seekToEndOfFile()

        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
    }

    deinit {
        try? fileHandle?.close()
    }

    public func info(_ message: String) {
        write("INFO", message)
    }

    public func warn(_ message: String) {
        write("WARN", message)
    }

    public func error(_ message: String) {
        write("ERROR", message)
    }

    private func write(_ level: String, _ message: String) {
        // All access to dateFormatter and fileHandle on the serial queue
        // to guarantee thread safety (DateFormatter is not thread-safe).
        queue.async { [weak self] in
            guard let self else { return }
            let timestamp = self.dateFormatter.string(from: Date())
            let line = "[\(timestamp)] [\(level)] \(message)\n"
            guard let data = line.data(using: .utf8) else { return }
            self.fileHandle?.write(data)
        }
    }

    private static func defaultLogDirectory() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("Deskjockey", isDirectory: true)
    }
}
