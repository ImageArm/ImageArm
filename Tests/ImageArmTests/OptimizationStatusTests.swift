import XCTest
@testable import ImageArm

final class OptimizationStatusTests: XCTestCase {

    // MARK: - isComplete

    func testPendingIsNotComplete() {
        XCTAssertFalse(OptimizationStatus.pending.isComplete)
    }

    func testProcessingIsNotComplete() {
        XCTAssertFalse(OptimizationStatus.processing(tool: "oxipng", step: 1, totalSteps: 3).isComplete)
    }

    func testDoneIsComplete() {
        XCTAssertTrue(OptimizationStatus.done(savedBytes: 1024).isComplete)
    }

    func testAlreadyOptimalIsComplete() {
        XCTAssertTrue(OptimizationStatus.alreadyOptimal.isComplete)
    }

    func testFailedIsComplete() {
        XCTAssertTrue(OptimizationStatus.failed("erreur").isComplete)
    }

    // MARK: - progress

    func testPendingProgressIsZero() {
        XCTAssertEqual(OptimizationStatus.pending.progress, 0)
    }

    func testProcessingProgress() {
        let status = OptimizationStatus.processing(tool: "pngquant", step: 2, totalSteps: 4)
        XCTAssertEqual(status.progress, 0.5, accuracy: 0.001)
    }

    func testProcessingProgressZeroSteps() {
        let status = OptimizationStatus.processing(tool: "test", step: 0, totalSteps: 0)
        XCTAssertEqual(status.progress, 0)
    }

    func testDoneProgressIsOne() {
        XCTAssertEqual(OptimizationStatus.done(savedBytes: 500).progress, 1)
    }

    func testAlreadyOptimalProgressIsOne() {
        XCTAssertEqual(OptimizationStatus.alreadyOptimal.progress, 1)
    }

    // MARK: - currentTool

    func testCurrentToolWhenProcessing() {
        let status = OptimizationStatus.processing(tool: "svgo", step: 1, totalSteps: 1)
        XCTAssertEqual(status.currentTool, "svgo")
    }

    func testCurrentToolWhenNotProcessing() {
        XCTAssertNil(OptimizationStatus.pending.currentTool)
        XCTAssertNil(OptimizationStatus.done(savedBytes: 0).currentTool)
    }

    // MARK: - stepInfo

    func testStepInfo() {
        let status = OptimizationStatus.processing(tool: "oxipng", step: 2, totalSteps: 5)
        XCTAssertEqual(status.stepInfo, "oxipng (2/5)")
    }

    func testStepInfoNilWhenNotProcessing() {
        XCTAssertNil(OptimizationStatus.pending.stepInfo)
    }
}
