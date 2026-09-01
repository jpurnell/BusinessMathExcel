import XCTest
@testable import BusinessMathExcel
import SwiftXLSX

/// Whether a series' cells share one formula shape across the timeline.
final class FormulaUniformityTests: XCTestCase {

    private func uniformity(
        _ build: (Worksheet) -> Void
    ) -> (report: [FormulaUniformity], diagnostics: [Diagnostic]) {
        let wb = Workbook()
        let sheet = wb.addSheet(name: "Model")
        build(sheet)
        let grid = SheetGrid.build(from: ModelImporter.importSheet(sheet))
        guard let axis = PeriodAxis.build(from: grid).axis else { return ([], []) }
        let (series, _) = LabeledSeries.bind(in: grid, axis: axis)
        return FormulaUniformity.assess(series, in: grid)
    }

    private func withAxis(_ sheet: Worksheet) {
        sheet.write("2024", to: "C1")
        sheet.write("2025", to: "D1")
        sheet.write("2026", to: "E1")
    }

    func testARowOfTheSameFormulaShapeIsUniform() throws {
        let result = uniformity { sheet in
            withAxis(sheet)
            sheet.write("Base", to: "A2")
            for column in ["C", "D", "E"] { sheet.write(10.0, to: "\(column)2") }
            sheet.write("Doubled", to: "A3")
            // Each cell doubles the one above it — same shape, shifted one column.
            for column in ["C", "D", "E"] {
                sheet.write(
                    FormulaAST.multiply(.cellRef(CellRef("\(column)2")), .number(2)),
                    to: "\(column)3")
            }
        }

        let doubled = try XCTUnwrap(result.report.first { $0.series.name == "Doubled" })
        XCTAssertTrue(doubled.isUniform, "Same shape modulo column offset")
        XCTAssertTrue(result.diagnostics.isEmpty, "Got: \(result.diagnostics)")
    }

    func testOneHandEditedCellBreaksTheRow() throws {
        let result = uniformity { sheet in
            withAxis(sheet)
            sheet.write("Base", to: "A2")
            for column in ["C", "D", "E"] { sheet.write(10.0, to: "\(column)2") }
            sheet.write("Doubled", to: "A3")
            sheet.write(FormulaAST.multiply(.cellRef(CellRef("C2")), .number(2)), to: "C3")
            // D3 was overtyped with a different multiplier — the classic hand edit.
            sheet.write(FormulaAST.multiply(.cellRef(CellRef("D2")), .number(3)), to: "D3")
            sheet.write(FormulaAST.multiply(.cellRef(CellRef("E2")), .number(2)), to: "E3")
        }

        let doubled = try XCTUnwrap(result.report.first { $0.series.name == "Doubled" })
        XCTAssertFalse(doubled.isUniform)
        XCTAssertEqual(result.diagnostics.map(\.code), [.nonUniformRow])
        XCTAssertEqual(
            result.diagnostics.first?.cell, CellRef("D3"),
            "The diagnostic names the cell that broke the row"
        )
    }

    func testTheRecognizerNeverPicksAMajorityShape() throws {
        // Two cells agree and one does not. A majority vote would silently adopt
        // the two and rewrite the third; decision D10 forbids that.
        let result = uniformity { sheet in
            withAxis(sheet)
            sheet.write("Base", to: "A2")
            for column in ["C", "D", "E"] { sheet.write(10.0, to: "\(column)2") }
            sheet.write("Doubled", to: "A3")
            sheet.write(FormulaAST.multiply(.cellRef(CellRef("C2")), .number(2)), to: "C3")
            sheet.write(FormulaAST.multiply(.cellRef(CellRef("D2")), .number(2)), to: "D3")
            sheet.write(FormulaAST.add(.cellRef(CellRef("E2")), .number(99)), to: "E3")
        }

        let doubled = try XCTUnwrap(result.report.first { $0.series.name == "Doubled" })
        XCTAssertFalse(doubled.isUniform, "No majority rules")
        XCTAssertNil(doubled.shape, "And no shape is adopted")
    }

    func testARowOfPlainValuesIsUniform() throws {
        let result = uniformity { sheet in
            withAxis(sheet)
            sheet.write("Inputs", to: "A2")
            for column in ["C", "D", "E"] { sheet.write(10.0, to: "\(column)2") }
        }

        let inputs = try XCTUnwrap(result.report.first { $0.series.name == "Inputs" })
        XCTAssertTrue(inputs.isUniform, "An input row has one shape: a literal per period")
    }

    func testARowMixingValuesAndFormulasIsNotUniform() throws {
        // The seed-plus-rollforward shape: a typed first period, computed after.
        // Honest to report as non-uniform — the row does not reduce to one formula.
        let result = uniformity { sheet in
            withAxis(sheet)
            sheet.write("Revenue", to: "A2")
            sheet.write(100.0, to: "C2")
            sheet.write(FormulaAST.multiply(.cellRef(CellRef("C2")), .number(11)), to: "D2")
            sheet.write(FormulaAST.multiply(.cellRef(CellRef("D2")), .number(11)), to: "E2")
        }

        let revenue = try XCTUnwrap(result.report.first { $0.series.name == "Revenue" })
        XCTAssertFalse(revenue.isUniform)
        XCTAssertEqual(
            revenue.kind, .seededRollforward,
            "A typed opening period followed by one rule applied forward is a structure the "
                + "model layer expresses, not a hand edit"
        )
        XCTAssertTrue(
            result.diagnostics.isEmpty,
            "So it must not be reported as a non-uniform row"
        )
    }

    func testAHandEditAfterTheSeedIsStillNonUniform() throws {
        // Seed, then two periods that disagree with each other: not a rollforward.
        let result = uniformity { sheet in
            withAxis(sheet)
            sheet.write("Revenue", to: "A2")
            sheet.write(100.0, to: "C2")
            sheet.write(FormulaAST.multiply(.cellRef(CellRef("C2")), .number(11)), to: "D2")
            sheet.write(FormulaAST.multiply(.cellRef(CellRef("D2")), .number(12)), to: "E2")
        }

        let revenue = try XCTUnwrap(result.report.first { $0.series.name == "Revenue" })
        XCTAssertEqual(revenue.kind, .nonUniform)
        XCTAssertEqual(result.diagnostics.map(\.code), [.nonUniformRow])
    }

    func testAHoleDoesNotBreakUniformity() throws {
        let result = uniformity { sheet in
            withAxis(sheet)
            sheet.write("Base", to: "A2")
            for column in ["C", "D", "E"] { sheet.write(10.0, to: "\(column)2") }
            sheet.write("Doubled", to: "A3")
            sheet.write(FormulaAST.multiply(.cellRef(CellRef("C2")), .number(2)), to: "C3")
            // D3 blank
            sheet.write(FormulaAST.multiply(.cellRef(CellRef("E2")), .number(2)), to: "E3")
        }

        let doubled = try XCTUnwrap(result.report.first { $0.series.name == "Doubled" })
        XCTAssertTrue(doubled.isUniform, "A missing period is not a disagreement")
    }

    // MARK: - Absolute References

    func testAnAbsoluteReferenceRepeatedAcrossPeriodsIsUniform() throws {
        // `$D$1 * -1` in every period is one formula filled across. Computing a
        // relative offset for a pinned reference makes each cell look different
        // and reports an untouched row as hand-edited.
        let result = uniformity { sheet in
            withAxis(sheet)
            sheet.write(7.0, to: "A9")
            sheet.write("Fixed cost", to: "A2")
            for column in ["C", "D", "E"] {
                sheet.write(
                    FormulaAST.multiply(.cellRef(CellRef("$A$9")), .number(-1)),
                    to: "\(column)2")
            }
        }

        let series = try XCTUnwrap(result.report.first { $0.series.name == "Fixed cost" })
        XCTAssertTrue(series.isUniform, "A pinned reference does not shift when filled")
        XCTAssertTrue(result.diagnostics.isEmpty, "Got: \(result.diagnostics)")
    }

    func testAbsoluteAndRelativeReferencesAreDistinguished() throws {
        // Same target cell, but one period pins it and the others do not. Filling
        // these would not produce each other, so they are genuinely different shapes.
        let result = uniformity { sheet in
            withAxis(sheet)
            sheet.write("Base", to: "A2")
            for column in ["C", "D", "E"] { sheet.write(10.0, to: "\(column)2") }
            sheet.write("Mixed", to: "A3")
            sheet.write(FormulaAST.multiply(.cellRef(CellRef("$C$2")), .number(2)), to: "C3")
            sheet.write(FormulaAST.multiply(.cellRef(CellRef("D2")), .number(2)), to: "D3")
            sheet.write(FormulaAST.multiply(.cellRef(CellRef("E2")), .number(2)), to: "E3")
        }

        let series = try XCTUnwrap(result.report.first { $0.series.name == "Mixed" })
        XCTAssertFalse(series.isUniform)
        XCTAssertEqual(
            series.divergentCells, [CellRef("D3"), CellRef("E3")],
            "Both differ from the first cell seen. D3 and E3 agreeing with each other does not "
                + "make C3 the outlier — deciding that would be the majority vote D10 forbids."
        )
    }

    func testAPartiallyAbsoluteReferenceKeepsOnlyItsPinnedComponent() throws {
        // `D$1` pins the row and lets the column travel — the shape is the same
        // across a fill, because the free component moves with the cell.
        let result = uniformity { sheet in
            withAxis(sheet)
            sheet.write("Row-pinned", to: "A2")
            for column in ["C", "D", "E"] {
                sheet.write(FormulaAST.cellRef(CellRef("\(column)$1")), to: "\(column)2")
            }
        }

        let series = try XCTUnwrap(result.report.first { $0.series.name == "Row-pinned" })
        XCTAssertTrue(series.isUniform)
    }
}
