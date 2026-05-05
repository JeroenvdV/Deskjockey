import XCTest
@testable import DeskjockeyCore

final class FileLoggerTests: XCTestCase {

    private var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        // Create a temporary directory for test logs
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DeskjockeyTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        tempDirectory = tempDir
    }

    override func tearDown() {
        // Clean up temporary directory
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }

    // Wait for async file writes to complete
    private func waitForFileLogger() {
        let expectation = XCTestExpectation(description: "Wait for async file writes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 0.5)
    }

    func testFileLoggerCreatesLogFile() {
        let logger = FileLogger(directory: tempDirectory)
        logger.info("Test message")
        waitForFileLogger()

        let logFile = tempDirectory.appendingPathComponent("deskjockey.log")
        XCTAssertTrue(FileManager.default.fileExists(atPath: logFile.path))
    }

    func testFileLoggerWritesInfoMessage() {
        let logger = FileLogger(directory: tempDirectory)
        logger.info("Info test message")
        waitForFileLogger()

        let logFile = tempDirectory.appendingPathComponent("deskjockey.log")
        let content = try? String(contentsOf: logFile)
        XCTAssertTrue(content?.contains("INFO") ?? false)
        XCTAssertTrue(content?.contains("Info test message") ?? false)
    }

    func testFileLoggerWritesErrorMessage() {
        let logger = FileLogger(directory: tempDirectory)
        logger.error("Error test message")
        waitForFileLogger()

        let logFile = tempDirectory.appendingPathComponent("deskjockey.log")
        let content = try? String(contentsOf: logFile)
        XCTAssertTrue(content?.contains("ERROR") ?? false)
        XCTAssertTrue(content?.contains("Error test message") ?? false)
    }

    func testFileLoggerWritesWarningMessage() {
        let logger = FileLogger(directory: tempDirectory)
        logger.warn("Warning test message")
        waitForFileLogger()

        let logFile = tempDirectory.appendingPathComponent("deskjockey.log")
        let content = try? String(contentsOf: logFile)
        XCTAssertTrue(content?.contains("WARN") ?? false)
        XCTAssertTrue(content?.contains("Warning test message") ?? false)
    }

    func testFileLoggerIncludesTimestamp() {
        let logger = FileLogger(directory: tempDirectory)
        logger.info("Timestamp test")
        waitForFileLogger()

        let logFile = tempDirectory.appendingPathComponent("deskjockey.log")
        let content = try? String(contentsOf: logFile)
        // Check for timestamp pattern: yyyy-MM-dd HH:mm:ss.SSS
        XCTAssertTrue(content?.contains("20") ?? false)  // Year should be present
        XCTAssertTrue(content?.contains(":") ?? false)    // Time separator
    }

    func testFileLoggerAppendsToExistingFile() {
        let logger = FileLogger(directory: tempDirectory)
        logger.info("First message")
        logger.info("Second message")
        waitForFileLogger()

        let logFile = tempDirectory.appendingPathComponent("deskjockey.log")
        let content = try? String(contentsOf: logFile)
        XCTAssertTrue(content?.contains("First message") ?? false)
        XCTAssertTrue(content?.contains("Second message") ?? false)
        // Second message should appear after first
        let lines = content?.components(separatedBy: .newlines) ?? []
        let firstIndex = lines.firstIndex { $0.contains("First message") }
        let secondIndex = lines.firstIndex { $0.contains("Second message") }
        XCTAssertNotNil(firstIndex)
        XCTAssertNotNil(secondIndex)
        XCTAssertLessThan(firstIndex!, secondIndex!)
    }

    func testFileLoggerHandlesMultiLineMessages() {
        let logger = FileLogger(directory: tempDirectory)
        logger.info("Line 1\nLine 2\nLine 3")
        waitForFileLogger()

        let logFile = tempDirectory.appendingPathComponent("deskjockey.log")
        let content = try? String(contentsOf: logFile)
        XCTAssertTrue(content?.contains("Line 1") ?? false)
        XCTAssertTrue(content?.contains("Line 2") ?? false)
        XCTAssertTrue(content?.contains("Line 3") ?? false)
    }

    func testFileLoggerCreatesParentDirectories() {
        let nestedDir = tempDirectory
            .appendingPathComponent("nested", isDirectory: true)
            .appendingPathComponent("logs", isDirectory: true)
        
        // Ensure the directory doesn't exist initially
        try? FileManager.default.removeItem(at: nestedDir)

        let logger = FileLogger(directory: nestedDir)
        logger.info("Test message in nested directory")
        waitForFileLogger()

        let logFile = nestedDir.appendingPathComponent("deskjockey.log")
        XCTAssertTrue(FileManager.default.fileExists(atPath: logFile.path))
    }

    func testNullLoggerDoesNotCrash() {
        let logger = NullLogger()
        
        // These should not crash
        logger.info("Test")
        logger.warn("Test")
        logger.error("Test")
    }
}
