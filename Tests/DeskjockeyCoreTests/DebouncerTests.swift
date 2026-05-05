import XCTest
@testable import DeskjockeyCore

final class DebouncerTests: XCTestCase {

    func testDebouncerDelaysAction() {
        let expectation = XCTestExpectation(description: "Action should be executed after delay")
        let debouncer = Debouncer(delay: 0.1)
        var actionCalled = false

        debouncer.schedule {
            actionCalled = true
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 0.2)
        XCTAssertTrue(actionCalled)
    }

    func testDebouncerCoalescesRapidCalls() {
        let expectation = XCTestExpectation(description: "Only last action should be executed")
        let debouncer = Debouncer(delay: 0.1)
        var callCount = 0

        // Schedule multiple actions rapidly
        for i in 0..<10 {
            debouncer.schedule {
                callCount += 1
                if i == 9 {
                    expectation.fulfill()
                }
            }
        }

        wait(for: [expectation], timeout: 0.25)
        XCTAssertEqual(callCount, 1, "Only the last action should be executed")
    }

    func testDebouncerCancelsPreviousAction() {
        let expectation = XCTestExpectation(description: "Only second action should be executed")
        let debouncer = Debouncer(delay: 0.2)
        var callCount = 0

        debouncer.schedule {
            callCount += 1
        }

        // Schedule a second action before the first delay completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            debouncer.schedule {
                callCount += 1
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 0.4)
        XCTAssertEqual(callCount, 1, "Only the second action should be executed")
    }

    func testMultipleDebouncesAreIndependent() {
        let debouncer1 = Debouncer(delay: 0.1)
        let debouncer2 = Debouncer(delay: 0.1)
        let expectation1 = XCTestExpectation(description: "First debouncer action")
        let expectation2 = XCTestExpectation(description: "Second debouncer action")
        var count1 = 0
        var count2 = 0

        debouncer1.schedule {
            count1 += 1
            expectation1.fulfill()
        }

        debouncer2.schedule {
            count2 += 1
            expectation2.fulfill()
        }

        wait(for: [expectation1, expectation2], timeout: 0.25)
        XCTAssertEqual(count1, 1)
        XCTAssertEqual(count2, 1)
    }
}
