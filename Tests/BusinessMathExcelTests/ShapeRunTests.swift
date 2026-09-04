import XCTest
@testable import BusinessMathExcel
import BusinessMath
import SwiftXLSX

/// Runs of cells computing the same way.
///
/// A rule filled across a row is the same formula in every column. That is a fact
/// about the formulas, not about the labels above them — which matters because
/// `PeriodAxis` reads a timeline off a header row, and on most real workbooks
/// there either is no such row or it says something the detector does not expect:
/// `0, 1, 2 …` period indices on a teaching model, `FYE`/`LTM` on a credit model.
///
/// Three cells side by side sharing one shape are three periods of one account,
/// whatever sits above them.
final class ShapeRunTests: XCTestCase {

    private func grid(_ build: (Worksheet) -> Void) -> SheetGrid {
        let workbook = Workbook()
        let sheet = workbook.addSheet(name: "Model")
        build(sheet)
        return SheetGrid.build(from: ModelImporter.importSheet(sheet))
    }

    /// `= <column>1 * 2`, written across the given columns of one row.
    private func fillAcross(
        _ sheet: Worksheet, row: Int, columns: [String],
        _ formula: (String) -> FormulaAST
    ) {
        for column in columns { sheet.write(formula(column), to: "\(column)\(row)") }
    }

    // MARK: - Finding a run

    func testCellsComputingTheSameWayFormARun() {
        let grid = grid { sheet in
            fillAcross(sheet, row: 5, columns: ["C", "D", "E", "F"]) { column in
                .multiply(.cellRef(CellRef("\(column)4")), .number(2))
            }
        }

        let runs = ShapeRun.find(in: grid)
        XCTAssertEqual(runs.count, 1, "Got: \(runs)")

        let run = runs[0]
        XCTAssertEqual(run.line, 5)
        XCTAssertEqual(run.orientation, .periodsAcrossColumns)
        XCTAssertEqual(run.positions, 3...6, "columns C through F")
        XCTAssertEqual(run.length, 4)
    }

    /// Two is a coincidence. Three is the smallest thing that can be a timeline,
    /// and a rule written twice is as likely to be a pair of one-offs.
    func testTwoCellsAreNotARun() {
        let grid = grid { sheet in
            fillAcross(sheet, row: 5, columns: ["C", "D"]) { column in
                .multiply(.cellRef(CellRef("\(column)4")), .number(2))
            }
        }
        XCTAssertTrue(ShapeRun.find(in: grid).isEmpty)
    }

    func testFormulasThatDifferYieldNoRun() {
        let grid = grid { sheet in
            sheet.write(FormulaAST.multiply(.cellRef(CellRef("C4")), .number(2)), to: "C5")
            sheet.write(FormulaAST.add(.cellRef(CellRef("D4")), .number(2)), to: "D5")
            sheet.write(FormulaAST.divide(.cellRef(CellRef("E4")), .number(2)), to: "E5")
        }
        XCTAssertTrue(ShapeRun.find(in: grid).isEmpty)
    }

    /// A gap ends a run. Adjacency is what makes a run a *span* rather than a set.
    func testAGapBreaksARunInTwo() {
        let grid = grid { sheet in
            fillAcross(sheet, row: 5, columns: ["C", "D", "E"]) { column in
                .multiply(.cellRef(CellRef("\(column)4")), .number(2))
            }
            // G is missing, so H..J is a separate span.
            fillAcross(sheet, row: 5, columns: ["H", "I", "J"]) { column in
                .multiply(.cellRef(CellRef("\(column)4")), .number(2))
            }
        }

        let runs = ShapeRun.find(in: grid).sorted { $0.positions.lowerBound < $1.positions.lowerBound }
        XCTAssertEqual(runs.count, 2, "Got: \(runs.map(\.positions))")
        XCTAssertEqual(runs.first?.positions, 3...5)
        XCTAssertEqual(runs.last?.positions, 8...10)
    }

    /// An absolute reference is the same in every column, which is what pinning
    /// means — so it holds a run together rather than breaking it.
    func testAPinnedReferenceDoesNotBreakARun() {
        let grid = grid { sheet in
            fillAcross(sheet, row: 5, columns: ["C", "D", "E"]) { column in
                .multiply(.cellRef(CellRef("\(column)4")), .cellRef(CellRef("$B$1")))
            }
        }
        XCTAssertEqual(ShapeRun.find(in: grid).count, 1)
    }

    /// And a relative reference that does *not* move breaks one, because then the
    /// cells genuinely are computing different things.
    func testAReferenceThatShouldMoveAndDoesNotBreaksARun() {
        let grid = grid { sheet in
            for column in ["C", "D", "E"] {
                sheet.write(
                    FormulaAST.multiply(.cellRef(CellRef("B4")), .number(2)),
                    to: "\(column)5")
            }
        }
        XCTAssertTrue(
            ShapeRun.find(in: grid).isEmpty,
            "three cells all reading B4 are three different rules relative to themselves")
    }

    // MARK: - Down columns

    /// A model may run either way, and the sheet decides — so runs are found down
    /// columns too, not only across rows.
    func testRunsAreFoundDownColumnsAsWell() {
        let grid = grid { sheet in
            for row in 4...7 {
                sheet.write(
                    FormulaAST.multiply(.cellRef(CellRef("B\(row)")), .number(2)),
                    to: "C\(row)")
            }
        }

        let down = ShapeRun.find(in: grid).filter { $0.orientation == .periodsDownRows }
        XCTAssertEqual(down.count, 1, "Got: \(ShapeRun.find(in: grid))")
        XCTAssertEqual(down.first?.line, 3, "column C")
        XCTAssertEqual(down.first?.positions, 4...7)
    }

    // MARK: - Several rows

    func testEachRowYieldsItsOwnRun() {
        let grid = grid { sheet in
            for row in [5, 6, 7] {
                fillAcross(sheet, row: row, columns: ["C", "D", "E"]) { column in
                    .multiply(.cellRef(CellRef("\(column)\(row - 1)")), .number(2))
                }
            }
        }

        let across = ShapeRun.find(in: grid).filter { $0.orientation == .periodsAcrossColumns }
        XCTAssertEqual(across.count, 3)
        XCTAssertEqual(Set(across.map(\.positions)), [3...5], "all agreeing on one span")
    }

    func testASheetWithNoFormulasHasNoRuns() {
        let grid = grid { sheet in
            sheet.write("Revenue", to: "A1")
            sheet.write(100.0, to: "B1")
        }
        XCTAssertTrue(ShapeRun.find(in: grid).isEmpty)
    }

    // MARK: - The span the runs agree on

    private func run(
        line: Int, _ positions: ClosedRange<Int>,
        _ orientation: SheetGrid.Orientation = .periodsAcrossColumns,
        shape: String = "RC[-1]*2"
    ) -> ShapeRun {
        ShapeRun(line: line, positions: positions, orientation: orientation, shape: shape)
    }

    /// The timeline is the span the sheet's own arithmetic asserts most often.
    ///
    /// The count matters as much as the span. It is the evidence, and a caller
    /// weighing a derived axis against a header one needs to see how much of the
    /// sheet stood behind it.
    func testTheSpanTheMostRunsAgreeOnIsTheAxis() {
        let runs = [
            run(line: 5, 3...6),
            run(line: 6, 3...6),
            run(line: 7, 3...6),
            run(line: 9, 10...14, shape: "SUM(RC[-3]:RC[-1])"),
        ]

        let consensus = ShapeRun.consensus(among: runs)
        XCTAssertEqual(consensus?.positions, 3...6)
        XCTAssertEqual(consensus?.orientation, .periodsAcrossColumns)
        XCTAssertEqual(consensus?.agreeing, 3, "three rows stood behind it")
    }

    /// One run agreeing with itself is not evidence of anything.
    func testASingleRunDerivesNothing() {
        XCTAssertNil(ShapeRun.consensus(among: [run(line: 5, 3...6)]))
    }

    /// The floor is the same argument as ``ShapeRun/minimumLength``, applied to
    /// rows instead of cells: two is a coincidence, three is a rule.
    func testTwoAgreeingRunsAreBelowTheFloor() {
        let runs = [run(line: 5, 3...6), run(line: 6, 3...6)]
        XCTAssertNil(ShapeRun.consensus(among: runs))
    }

    /// A tie is the sheet declining to name one timeline, and guessing between two
    /// equally-supported spans would be exactly the assertion this phase refuses to
    /// make elsewhere.
    func testTwoEquallySupportedSpansDeriveNothing() {
        let runs = [
            run(line: 5, 3...6), run(line: 6, 3...6), run(line: 7, 3...6),
            run(line: 20, 10...14), run(line: 21, 10...14), run(line: 22, 10...14),
        ]
        XCTAssertNil(ShapeRun.consensus(among: runs))
    }

    /// A span of columns and a span of rows are different findings even when the
    /// integers coincide, so they are counted apart.
    func testOrientationIsPartOfWhatRunsAgreeOn() {
        let runs = [
            run(line: 5, 3...6), run(line: 6, 3...6), run(line: 7, 3...6),
            run(line: 40, 3...6, .periodsDownRows),
            run(line: 41, 3...6, .periodsDownRows),
        ]

        let consensus = ShapeRun.consensus(among: runs)
        XCTAssertEqual(consensus?.orientation, .periodsAcrossColumns)
        XCTAssertEqual(consensus?.agreeing, 3, "the two down-column runs are a separate tally")
    }

    func testNoRunsDeriveNothing() {
        XCTAssertNil(ShapeRun.consensus(among: []))
    }
}
