import XCTest
@testable import BusinessMathExcel
import BusinessMath
import SwiftXLSX

/// The emitted source compiles, and computes what the plan computes.
///
/// ## Why a checked-in file rather than a compiler run
///
/// The claim worth testing is that ``TypedSourceWriter`` produces Swift that
/// **builds**, and nothing short of a compiler can say so. Spawning one from a
/// test is the obvious approach and is not available: an unbounded `Process` is
/// refused by the safety checker, correctly — `readDataToEndOfFile` waits on every
/// inherited write end and cannot be bounded — and `ProcessRunner`, the sanctioned
/// way, lives in the quality-gate tool rather than in a package under test.
///
/// So the compiler that checks the output is the one already compiling this
/// target. `GoldenForecastModel.swift` is the writer's output, checked in and
/// built as ordinary source. If it stopped compiling, the test target would stop
/// building, which is a louder failure than an assertion.
///
/// That leaves one gap — the checked-in file could drift from what the writer now
/// emits — and ``testTheWriterStillEmitsTheGolden`` closes it by regenerating and
/// comparing. Together the two say: this exact text compiles, and this is still
/// the text the writer produces.
final class GoldenSourceTests: XCTestCase {

    /// The workbook `GoldenForecastModel.swift` was generated from.
    ///
    /// Revenue grows 15% a year off a stated first period; EBITDA is a margin on
    /// it. Small on purpose — the file is read by a person when this test fails.
    private func fixture() -> Workbook {
        let workbook = Workbook()
        let sheet = workbook.addSheet(name: "Forecast")
        let money = CellStyle.general.with(numberFormat: .currency)
        let percent = CellStyle.general.with(numberFormat: .percent)

        sheet.write("2024", to: "C5")
        sheet.write("2025", to: "D5")
        sheet.write("2026", to: "E5")

        sheet.write("Revenue growth", to: "A2")
        sheet.write(0.15, to: "B2", style: percent)
        sheet.write("EBITDA margin", to: "A3")
        sheet.write(0.4, to: "B3", style: percent)

        sheet.write("Revenue", to: "B6")
        sheet.write(1_000_000.0, to: "C6", style: money)
        sheet.write(
            FormulaAST.multiply(.cellRef(CellRef("C6")), .number(1.15)), to: "D6", style: money)
        sheet.write(
            FormulaAST.multiply(.cellRef(CellRef("D6")), .number(1.15)), to: "E6", style: money)

        sheet.write("EBITDA", to: "B7")
        for column in ["C", "D", "E"] {
            sheet.write(
                FormulaAST.multiply(
                    .cellRef(CellRef("\(column)6")), .cellRef(CellRef("$B$3"))),
                to: "\(column)7", style: money)
        }
        return workbook
    }

    private func plan() throws -> RecognizedModel {
        let workbook = fixture()
        let sheet = try XCTUnwrap(workbook.sheets.first)
        return ExcelRecognizer.recognize(sheet, in: workbook).model
    }

    // MARK: - It runs

    /// The generated model computes, and computes the right numbers.
    ///
    /// These are the same figures the golden path pins: Excel's own
    /// 1,000,000 / 1,150,000 / 1,322,500, with a 40% margin on each.
    func testTheGeneratedModelRuns() throws {
        let results = try GoldenForecast.run()

        let revenue = try XCTUnwrap(results["Revenue"]?.valuesArray)
        XCTAssertEqual(revenue.count, 3)
        for (actual, expected) in zip(revenue, [1_000_000.0, 1_150_000, 1_322_500]) {
            XCTAssertEqual(actual, expected, accuracy: 1e-6)
        }

        let ebitda = try XCTUnwrap(results["EBITDA"]?.valuesArray)
        for (actual, expected) in zip(ebitda, [400_000.0, 460_000, 529_000]) {
            XCTAssertEqual(actual, expected, accuracy: 1e-6)
        }
    }

    /// The generated model agrees with materializing the plan directly.
    ///
    /// Compared against each other rather than against constants. A constant would
    /// pass if both drifted together; this cannot, which is the point — the writer
    /// is a second route to the same model and has to stay one.
    func testTheGeneratedModelAgreesWithTheMaterializedPlan() throws {
        let built = try ModelMaterializer.build(from: try plan())
        let materialized = try PeriodDriver(
            definition: built.definition, rollforwards: built.rollforwards
        ).run(over: built.periods)

        let generated = try GoldenForecast.run()

        XCTAssertEqual(
            Set(generated.keys), Set(materialized.keys),
            "both routes produce the same accounts")

        for (name, series) in materialized {
            let emitted = try XCTUnwrap(generated[name]?.valuesArray, "\(name) is missing")
            for (actual, expected) in zip(emitted, series.valuesArray) {
                XCTAssertEqual(actual, expected, accuracy: 1e-9, "\(name)")
            }
        }
    }

    /// The generated model passes the unit check it emits a call to.
    func testTheGeneratedModelValidates() throws {
        let model = GoldenForecast.definition()
        XCTAssertNoThrow(try model.validateUnits())
        XCTAssertFalse(
            model.unitDeclarations.isEmpty,
            "and it declared units rather than validating vacuously")
    }

    // MARK: - It is still what the writer emits

    /// The checked-in file is regenerated and compared, so it cannot go stale.
    ///
    /// Without this the golden would prove only that *some* output once compiled.
    /// With it, the compiling file and the current output are the same text.
    func testTheWriterStillEmitsTheGolden() throws {
        let emitted = TypedSourceWriter.swiftSource(
            for: try plan(), sheetName: "Forecast", modelName: "GoldenForecast")

        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("GoldenForecastModel.swift")
        let onDisk = try String(contentsOf: url, encoding: .utf8)

        XCTAssertEqual(
            emitted, onDisk,
            "GoldenForecastModel.swift has drifted from what the writer emits. If the "
                + "change is intended, regenerate it — but read the diff first: the file "
                + "is checked in precisely so a change to the writer shows up as one.")
    }
}
