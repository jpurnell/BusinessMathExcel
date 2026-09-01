import XCTest
@testable import BusinessMathExcel
import SwiftXLSX

/// ``Coverage`` and ``Diagnostic`` — the vocabulary every recognition stage
/// reports through.
final class RecognitionVocabularyTests: XCTestCase {

    // MARK: - Coverage

    func testCoverageFractionIsRecognizedOverPopulated() {
        let coverage = Coverage(populatedCells: 200, recognizedCells: 150)
        XCTAssertEqual(coverage.fraction, 0.75, accuracy: 1e-9)
    }

    func testCoverageOfAnEmptySheetIsZeroNotADivisionByZero() {
        let coverage = Coverage(populatedCells: 0, recognizedCells: 0)
        XCTAssertEqual(coverage.fraction, 0, accuracy: 1e-9)
        XCTAssertTrue(coverage.fraction.isFinite)
    }

    func testCoverageIsCompleteWhenEveryPopulatedCellIsRecognized() {
        let coverage = Coverage(populatedCells: 42, recognizedCells: 42)
        XCTAssertEqual(coverage.fraction, 1, accuracy: 1e-9)
        XCTAssertTrue(coverage.isComplete)
    }

    func testCoverageIsNotCompleteWhenAnythingIsMissed() {
        XCTAssertFalse(Coverage(populatedCells: 42, recognizedCells: 41).isComplete)
        XCTAssertFalse(Coverage(populatedCells: 0, recognizedCells: 0).isComplete)
    }

    // MARK: - Diagnostic

    func testDiagnosticCarriesItsCellAndCode() {
        let diagnostic = Diagnostic(
            severity: .warning,
            code: .ambiguousOrientation,
            cell: CellRef("B4"),
            message: "Rows and columns both read as a period axis"
        )
        XCTAssertEqual(diagnostic.severity, .warning)
        XCTAssertEqual(diagnostic.code, .ambiguousOrientation)
        XCTAssertEqual(diagnostic.cell, CellRef("B4"))
    }

    func testDiagnosticNeedsNoCellWhenTheFindingIsAboutTheSheet() {
        let diagnostic = Diagnostic(
            severity: .error,
            code: .noPeriodAxis,
            message: "No row or column reads as a period axis"
        )
        XCTAssertNil(diagnostic.cell)
    }

    func testEveryDiagnosticCodeHasAStableRawValue() {
        // The codes cross process boundaries via the MCP schema, so a rename is a
        // breaking change and should be visible as one.
        XCTAssertEqual(DiagnosticCode.nonUniformRow.rawValue, "nonUniformRow")
        XCTAssertEqual(DiagnosticCode.unregisteredFunction.rawValue, "unregisteredFunction")
        XCTAssertEqual(DiagnosticCode.dynamicReference.rawValue, "dynamicReference")
    }

    func testDiagnosticCodeEnumeratesTheCodesLaterStagesOwn() {
        // Stage 3 owns these, but a CaseIterable with holes invites a second enum
        // later, so the vocabulary is complete from the start.
        let codes = Set(DiagnosticCode.allCases)
        XCTAssertTrue(codes.contains(.dynamicReference))
        XCTAssertTrue(codes.contains(.foldedDynamicReference))
        XCTAssertTrue(codes.contains(.sensitivityMismatch))
        XCTAssertTrue(codes.contains(.unsupportedLag))
    }
}
