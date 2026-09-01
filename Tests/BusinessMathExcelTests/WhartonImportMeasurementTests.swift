import XCTest
@testable import BusinessMathExcel
import BusinessMath
import SwiftXLSX

/// Measures import fidelity against a workbook Excel actually wrote.
///
/// The rest of the suite builds workbooks with ``ModelExporter`` and reads them
/// back, which only ever exercises the shapes this package emits. This one reads
/// the Wharton LBO Practice Model — see `Tests/Fixtures/README.md` for how to
/// fetch it, and why it is not checked in.
///
/// These tests report a measurement rather than enforce a threshold. Coverage is
/// tracked as a progress metric toward 100%, not as a gate that fails a build.
final class WhartonImportMeasurementTests: XCTestCase {

    private static let fixtureName = "Wharton-LBO-Practice-Model.xlsx"

    private func fixture() throws -> Workbook {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(Self.fixtureName)")

        guard (try? url.checkResourceIsReachable()) == true else {
            throw XCTSkip(
                "\(Self.fixtureName) is not present. See Tests/Fixtures/README.md to fetch it."
            )
        }
        return try Workbook(contentsOf: url)
    }

    // MARK: - The Fixture Identifies Itself

    func testWorkbookHasTheExpectedSheets() throws {
        let workbook = try fixture()
        XCTAssertEqual(workbook.sheets.map(\.name), ["KEY NOTES", "BLANK MODEL", "ANSWER KEY"])
    }

    func testAnswerKeyCarriesThePublishedIRR() throws {
        let workbook = try fixture()
        let answerKey = try XCTUnwrap(workbook.sheets.first { $0.name == "ANSWER KEY" })

        // C64 = IRR(D61:I61). Excel's cached result is the published 24.67%, which
        // is what makes this the right file rather than merely a similar one.
        guard case .formula(_, let cached) = answerKey.cell(at: "C64"),
              case .number(let irr)? = cached else {
            return XCTFail("ANSWER KEY!C64 should be a formula with a cached value")
        }
        XCTAssertEqual(irr, 0.2467, accuracy: 0.0001)
    }

    // MARK: - Recognition

    func testRecognizesThePeriodAxisOnTheModelSheets() throws {
        let workbook = try fixture()
        for name in ["ANSWER KEY", "BLANK MODEL"] {
            let sheet = try XCTUnwrap(workbook.sheets.first { $0.name == name })
            let grid = SheetGrid.build(from: ModelImporter.importSheet(sheet))

            XCTAssertEqual(grid.orientation, .periodsAcrossColumns, name)
            XCTAssertEqual(grid.axisLine, 27, "\(name): the axis is row 27")
            XCTAssertEqual(
                grid.axisCells.map(\.reference), ["E27", "F27", "G27", "H27", "I27", "J27"],
                "\(name): 2023 through 2028"
            )
            XCTAssertTrue(grid.diagnostics.isEmpty, "\(name): \(grid.diagnostics)")
        }
    }

    func testTheNotesSheetHasNoPeriodAxis() throws {
        let workbook = try fixture()
        let sheet = try XCTUnwrap(workbook.sheets.first { $0.name == "KEY NOTES" })
        let grid = SheetGrid.build(from: ModelImporter.importSheet(sheet))

        XCTAssertNil(grid.orientation, "A page of prose is not a model")
        XCTAssertEqual(grid.diagnostics.map(\.code), [.noPeriodAxis])
    }

    func testTheAxisIsReadFromAComputedHeaderRow() throws {
        // Only E27 is a typed year; F27 onward are `=E27+1`. An axis detector that
        // ignored what the file recorded Excel computing would find nothing here,
        // which is the common case rather than the exotic one.
        let workbook = try fixture()
        let sheet = try XCTUnwrap(workbook.sheets.first { $0.name == "ANSWER KEY" })
        let result = ModelImporter.importSheet(sheet)

        XCTAssertNil(result.cachedValues[CellRef("E27")], "E27 is typed, not computed")
        XCTAssertEqual(result.cachedValues[CellRef("F27")], .number(2024))
    }

    func testRecoversTheModelsSixYearTimeline() throws {
        let workbook = try fixture()
        let sheet = try XCTUnwrap(workbook.sheets.first { $0.name == "ANSWER KEY" })
        let grid = SheetGrid.build(from: ModelImporter.importSheet(sheet))
        let (axis, diagnostics) = PeriodAxis.build(from: grid)

        let recovered = try XCTUnwrap(axis)
        XCTAssertEqual(recovered.count, 6, "2023 plus five projection years")
        XCTAssertEqual(recovered.granularity, .annual)
        XCTAssertEqual(recovered.periods, (2023...2028).map(Period.year))
        XCTAssertEqual(recovered.sources.map(\.reference), grid.axisCells.map(\.reference))
        XCTAssertTrue(diagnostics.isEmpty, "Got: \(diagnostics)")
    }

    // MARK: - Import Fidelity

    func testEveryPopulatedCellBecomesANode() throws {
        let workbook = try fixture()
        let answerKey = try XCTUnwrap(workbook.sheets.first { $0.name == "ANSWER KEY" })
        let result = ModelImporter.importSheet(answerKey)

        let populated = answerKey.cellReferences.filter { reference in
            guard let value = answerKey.cell(at: reference) else { return false }
            if case .blank = value { return false }
            return true
        }.count

        XCTAssertEqual(
            result.model.nodeCount, populated,
            "Structural transcription must not drop cells; interpretation happens above this layer"
        )
    }

    func testReportsImportFidelity() throws {
        let workbook = try fixture()
        let answerKey = try XCTUnwrap(workbook.sheets.first { $0.name == "ANSWER KEY" })
        let result = ModelImporter.importSheet(answerKey)

        var clean = 0
        var degraded = 0
        for ref in result.model.allRefs {
            guard case .formula(let formula) = result.model.kind(of: ref) else { continue }
            if Self.isDegraded(formula) { degraded += 1 } else { clean += 1 }
        }

        print("""
            WHARTON import fidelity (ANSWER KEY):
              nodes            \(result.model.nodeCount)
              formula nodes    \(clean + degraded)  (\(clean) translated, \(degraded) degraded)
              warnings         \(result.warnings.count)
            """)

        XCTAssertGreaterThan(clean, 0, "Some formulas must survive translation")
    }

    /// Whether a formula contains any of the importer's degrade sentinels.
    private static func isDegraded(_ formula: NodeFormula) -> Bool {
        switch formula {
        case .text(let value):
            return value == "UNSUPPORTED" || value == "DEPTH_EXCEEDED" || value.hasPrefix("REF:")
        case .add(let lhs, let rhs), .subtract(let lhs, let rhs),
             .multiply(let lhs, let rhs), .divide(let lhs, let rhs),
             .power(let lhs, let rhs),
             .equal(let lhs, let rhs), .notEqual(let lhs, let rhs),
             .greaterThan(let lhs, let rhs), .lessThan(let lhs, let rhs),
             .greaterOrEqual(let lhs, let rhs), .lessOrEqual(let lhs, let rhs):
            return isDegraded(lhs) || isDegraded(rhs)
        case .negate(let expr):
            return isDegraded(expr)
        case .function(_, let args):
            return args.contains(where: isDegraded)
        case .ref, .number, .bool, .range:
            return false
        }
    }
}
