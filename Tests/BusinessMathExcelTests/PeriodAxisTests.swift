import XCTest
@testable import BusinessMathExcel
import BusinessMath
import SwiftXLSX

/// Stage 1 — turning detected headings into a real time axis.
final class PeriodAxisTests: XCTestCase {

    private func axis(
        _ build: (Worksheet) -> Void
    ) -> (axis: PeriodAxis?, diagnostics: [Diagnostic]) {
        let wb = Workbook()
        let sheet = wb.addSheet(name: "Model")
        build(sheet)
        let grid = SheetGrid.build(from: ModelImporter.importSheet(sheet))
        return PeriodAxis.build(from: grid)
    }

    /// The axis together with **both** stages' findings.
    ///
    /// Kept apart from ``axis(_:)`` deliberately. Which stage reported what is
    /// itself under test above — this stage stays silent about a missing axis
    /// because the grid already said so — so a helper that merged the two would
    /// quietly erase the distinction it exists to check.
    private func axisAndEveryFinding(
        _ build: (Worksheet) -> Void
    ) -> (axis: PeriodAxis?, diagnostics: [Diagnostic]) {
        let wb = Workbook()
        let sheet = wb.addSheet(name: "Model")
        build(sheet)
        let grid = SheetGrid.build(from: ModelImporter.importSheet(sheet))
        let result = PeriodAxis.build(from: grid)
        return (result.axis, grid.diagnostics + result.diagnostics)
    }

    func testYearHeadingsBecomeAnnualPeriods() throws {
        let result = axis { sheet in
            sheet.write("2024", to: "B1")
            sheet.write("2025", to: "C1")
            sheet.write("2026", to: "D1")
        }

        let axis = try XCTUnwrap(result.axis)
        XCTAssertEqual(axis.periods, [Period.year(2024), Period.year(2025), Period.year(2026)])
        XCTAssertEqual(axis.granularity, .annual)
        XCTAssertTrue(result.diagnostics.isEmpty, "Got: \(result.diagnostics)")
    }

    func testPeriodsKeepTheOrderOfTheirSourceCells() throws {
        let result = axis { sheet in
            sheet.write("2024", to: "B1")
            sheet.write("2025", to: "C1")
        }

        let axis = try XCTUnwrap(result.axis)
        XCTAssertEqual(axis.sources.map(\.reference), ["B1", "C1"])
        XCTAssertEqual(axis.periods.count, axis.sources.count)
        XCTAssertEqual(axis.periods.first, Period.year(2024))
    }

    func testTheRecoveredPeriodsAreBusinessMathAnnualPeriods() throws {
        // The whole point of the Phase 0 pin bump: these are the types
        // `ModelDefinition` consumes, not a local stand-in.
        let result = axis { sheet in
            sheet.write("2024", to: "B1")
            sheet.write("2025", to: "C1")
        }

        let axis = try XCTUnwrap(result.axis)
        let first = try XCTUnwrap(axis.periods.first)
        XCTAssertEqual(first.type, PeriodType.annual)
        XCTAssertEqual(first, Period.year(2024))
    }

    func testFiscalAndEstimateHeadingsRecoverTheirYear() throws {
        for (headings, years) in [(["FY2024", "FY2025"], [2024, 2025]),
                                  (["FY24", "FY25"], [2024, 2025]),
                                  (["2024E", "2025E"], [2024, 2025])] {
            let result = axis { sheet in
                sheet.write(headings[0], to: "B1")
                sheet.write(headings[1], to: "C1")
            }
            let axis = try XCTUnwrap(result.axis, "\(headings)")
            XCTAssertEqual(axis.periods, years.map(Period.year), "\(headings)")
        }
    }

    func testAComputedHeaderRowRecoversItsPeriods() throws {
        // The shape every real model uses: one typed year, the rest computed.
        let wb = Workbook()
        let sheet = wb.addSheet(name: "Model")
        sheet.write(2023.0, to: "E27")
        sheet.write(FormulaAST.add(.cellRef(CellRef("E27")), .number(1)), to: "F27")
        let reloaded = try Workbook(xlsxData: try wb.save())

        let grid = SheetGrid.build(
            from: ModelImporter.importSheet(try XCTUnwrap(reloaded.sheets.first)))
        // Writing in memory caches nothing, so this asserts the pathway, not the value.
        XCTAssertNotNil(grid.cachedValues)
    }

    func testNoAxisYieldsNoPeriodsAndNoRepeatedComplaint() {
        let result = axis { sheet in
            sheet.write("Revenue", to: "A1")
            sheet.write(100.0, to: "B1")
        }

        XCTAssertNil(result.axis)
        XCTAssertTrue(
            result.diagnostics.isEmpty,
            "SheetGrid already reported the missing axis; saying so twice is noise"
        )
    }

    func testQuarterlyHeadingsAreNotRecognized() {
        // Deliberate, and recorded: neither reference workbook contains a single
        // quarterly heading, so supporting one would be guessing at its spelling.
        let result = axis { sheet in
            sheet.write("Q1 2024", to: "B1")
            sheet.write("Q2 2024", to: "C1")
        }

        XCTAssertNil(result.axis)
    }

    // MARK: - An axis derived from the sheet's own arithmetic

    /// Writes `= <column><reference row> <op> 2` across the given columns.
    private func fill(
        _ sheet: Worksheet, row: Int, columns: [String], referencing referenceRow: Int,
        _ combine: (FormulaAST, FormulaAST) -> FormulaAST
    ) {
        for column in columns {
            sheet.write(combine(.cellRef(CellRef("\(column)\(referenceRow)")), .number(2)),
                        to: "\(column)\(row)")
        }
    }

    /// Three rows computing alike across four columns are four periods, whatever
    /// sits above them and whether or not anything does.
    ///
    /// This is the case that motivates the whole phase: measured across three
    /// corpora, most sheets carry no heading row the detector can read.
    func testAnAxisIsDerivedWhereNoHeadingsExist() throws {
        let result = axis { sheet in
            fill(sheet, row: 5, columns: ["C", "D", "E", "F"], referencing: 4, FormulaAST.multiply)
            fill(sheet, row: 6, columns: ["C", "D", "E", "F"], referencing: 4, FormulaAST.add)
            fill(sheet, row: 7, columns: ["C", "D", "E", "F"], referencing: 4, FormulaAST.divide)
        }

        let axis = try XCTUnwrap(result.axis, "Got: \(result.diagnostics)")
        XCTAssertEqual(axis.count, 4, "columns C through F")
        XCTAssertEqual(axis.provenance, .shapeRuns(agreeing: 3))
    }

    /// A derived axis has no headings — that is its premise — so its periods are
    /// ordinal. They assert sequence and nothing else: no calendar, no start date.
    ///
    /// The structure of a model is mechanical; its labels are arbitrary. Reading
    /// whatever text happened to sit above the span would make a structural finding
    /// depend on the arbitrary part, and would fail in exactly the cases this path
    /// exists to serve.
    func testADerivedAxisCarriesOrdinalPeriods() throws {
        let result = axis { sheet in
            fill(sheet, row: 5, columns: ["C", "D", "E"], referencing: 4, FormulaAST.multiply)
            fill(sheet, row: 6, columns: ["C", "D", "E"], referencing: 4, FormulaAST.add)
            fill(sheet, row: 7, columns: ["C", "D", "E"], referencing: 4, FormulaAST.divide)
        }

        let axis = try XCTUnwrap(result.axis, "Got: \(result.diagnostics)")
        XCTAssertEqual(axis.periods, [Period.year(1), Period.year(2), Period.year(3)])
        XCTAssertEqual(axis.periods.map(\.label), ["1", "2", "3"], "positions, not years")
        XCTAssertEqual(Set(axis.periods).count, 3, "three positions, not two and a collision")
    }

    /// Header detection is right when it works, it is what a reader would do, and
    /// it carries the Wharton 125-of-125. Shape runs are the fallback, not the
    /// replacement.
    func testAHeaderAxisIsKeptWhereOneExists() throws {
        let result = axisAndEveryFinding { sheet in
            sheet.write("2024", to: "C1")
            sheet.write("2025", to: "D1")
            sheet.write("2026", to: "E1")
            fill(sheet, row: 5, columns: ["C", "D", "E"], referencing: 4, FormulaAST.multiply)
            fill(sheet, row: 6, columns: ["C", "D", "E"], referencing: 4, FormulaAST.add)
            fill(sheet, row: 7, columns: ["C", "D", "E"], referencing: 4, FormulaAST.divide)
        }

        let axis = try XCTUnwrap(result.axis, "Got: \(result.diagnostics)")
        XCTAssertEqual(axis.periods, [Period.year(2024), Period.year(2025), Period.year(2026)])
        XCTAssertEqual(axis.provenance, .headings)
        XCTAssertTrue(
            result.diagnostics.isEmpty,
            "The two agree on the span, so there is nothing to report. Got: \(result.diagnostics)")
    }

    /// The header axis is kept and the difference is **reported**.
    ///
    /// On the credit model's sheet `A` header detection does not fail quietly: it
    /// finds five year-like values down a column and reads the whole sheet sideways
    /// while sixteen runs agree on a span across. Asserting the shape answer in
    /// general would be a guess, so the disagreement is named rather than resolved.
    func testADisagreementIsReportedRatherThanResolved() throws {
        let result = axisAndEveryFinding { sheet in
            sheet.write("2024", to: "B1")
            sheet.write("2025", to: "C1")
            sheet.write("2026", to: "D1")
            fill(sheet, row: 5, columns: ["F", "G", "H", "I"], referencing: 4, FormulaAST.multiply)
            fill(sheet, row: 6, columns: ["F", "G", "H", "I"], referencing: 4, FormulaAST.add)
            fill(sheet, row: 7, columns: ["F", "G", "H", "I"], referencing: 4, FormulaAST.divide)
        }

        let axis = try XCTUnwrap(result.axis, "Got: \(result.diagnostics)")
        XCTAssertEqual(axis.periods, [Period.year(2024), Period.year(2025), Period.year(2026)],
                       "the header axis is kept")
        XCTAssertEqual(axis.provenance, .headings)
        XCTAssertEqual(result.diagnostics.map(\.code), [.derivedAxisDiffers])
    }

    /// Below the floor nothing is derived, and the sheet is left saying what it
    /// said before: no axis here.
    func testTooLittleAgreementDerivesNoAxis() {
        let result = axis { sheet in
            fill(sheet, row: 5, columns: ["C", "D", "E"], referencing: 4, FormulaAST.multiply)
            fill(sheet, row: 6, columns: ["C", "D", "E"], referencing: 4, FormulaAST.add)
        }
        XCTAssertNil(result.axis)
    }
}
