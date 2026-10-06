import Foundation
import Testing
@testable import BusinessMathExcel
import SwiftXLSX

/// ``Coverage`` and ``Diagnostic`` — the vocabulary every recognition stage
/// reports through.
@Suite struct RecognitionVocabularyTests {

    // MARK: - Coverage

    @Test func coverageFractionIsRecognizedOverPopulated() {
        let coverage = Coverage(populatedCells: 200, recognizedCells: 150)
        #expect(abs(coverage.fraction - 0.75) <= 1e-9)
    }

    @Test func coverageOfAnEmptySheetIsZeroNotADivisionByZero() {
        let coverage = Coverage(populatedCells: 0, recognizedCells: 0)
        #expect(abs(coverage.fraction - 0) <= 1e-9)
        #expect(coverage.fraction.isFinite)
    }

    @Test func coverageIsCompleteWhenEveryPopulatedCellIsRecognized() {
        let coverage = Coverage(populatedCells: 42, recognizedCells: 42)
        #expect(abs(coverage.fraction - 1) <= 1e-9)
        #expect(coverage.isComplete)
    }

    @Test func coverageIsNotCompleteWhenAnythingIsMissed() {
        #expect(!Coverage(populatedCells: 42, recognizedCells: 41).isComplete)
        #expect(!Coverage(populatedCells: 0, recognizedCells: 0).isComplete)
    }

    // MARK: - Diagnostic

    @Test func diagnosticCarriesItsCellAndCode() {
        let diagnostic = Diagnostic(
            severity: .warning,
            code: .ambiguousOrientation,
            cell: CellRef("B4"),
            message: "Rows and columns both read as a period axis"
        )
        #expect(diagnostic.severity == .warning)
        #expect(diagnostic.code == .ambiguousOrientation)
        #expect(diagnostic.cell == CellRef("B4"))
    }

    @Test func diagnosticNeedsNoCellWhenTheFindingIsAboutTheSheet() {
        let diagnostic = Diagnostic(
            severity: .error,
            code: .noPeriodAxis,
            message: "No row or column reads as a period axis"
        )
        #expect(diagnostic.cell == nil)
    }

    @Test func everyDiagnosticCodeHasAStableRawValue() {
        // The codes cross process boundaries via the MCP schema, so a rename is a
        // breaking change and should be visible as one.
        #expect(DiagnosticCode.nonUniformRow.rawValue == "nonUniformRow")
        #expect(DiagnosticCode.unregisteredFunction.rawValue == "unregisteredFunction")
        #expect(DiagnosticCode.dynamicReference.rawValue == "dynamicReference")
    }

    @Test func diagnosticCodeEnumeratesTheCodesLaterStagesOwn() {
        // Stage 3 owns these, but a CaseIterable with holes invites a second enum
        // later, so the vocabulary is complete from the start.
        let codes = Set(DiagnosticCode.allCases)
        #expect(codes.contains(.dynamicReference))
        #expect(codes.contains(.foldedDynamicReference))
        #expect(codes.contains(.sensitivityMismatch))
        #expect(codes.contains(.unsupportedLag))
    }
}
