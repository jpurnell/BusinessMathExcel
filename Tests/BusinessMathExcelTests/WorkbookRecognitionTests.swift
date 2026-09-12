import XCTest
@testable import BusinessMathExcel
import BusinessMath
import SwiftXLSX

/// Recognizing a workbook rather than a sheet.
///
/// Serious models separate concerns by sheet: data on one, the calculations that
/// read it on another. A 104-sheet media model measured for this work pairs every
/// metric — `Paid Cost - Data` feeding `Paid Cost - Input+Calc` — and routes the
/// lot into a consolidation sheet. Cross-sheet references were 0.78% of its edges
/// and carried its entire architecture.
///
/// Recognizing a sheet at a time cannot see that. Worse, it names accounts bare,
/// so two sheets with a `Revenue` row yield two accounts called `Revenue` — which
/// `validateUnits()` would then report as one account meaning two things.
final class WorkbookRecognitionTests: XCTestCase {

    /// A sheet with a timeline and one labelled row per name given.
    private func addSheet(
        _ workbook: Workbook, named name: String, rows: [(String, Double)]
    ) {
        let sheet = workbook.addSheet(name: name)
        for (column, year) in zip(["C", "D", "E"], ["2024", "2025", "2026"]) {
            sheet.write(year, to: "\(column)1")
        }
        for (offset, row) in rows.enumerated() {
            let line = 2 + offset
            sheet.write(row.0, to: "A\(line)")
            for column in ["C", "D", "E"] { sheet.write(row.1, to: "\(column)\(line)") }
        }
    }

    // MARK: - An account knows where it came from

    func testAnAccountCarriesItsSheet() throws {
        let workbook = Workbook()
        addSheet(workbook, named: "Forecast", rows: [("Revenue", 1_000)])

        let plan = ExcelRecognizer.recognize(try XCTUnwrap(workbook.sheets.first), in: workbook)
        let revenue = try XCTUnwrap(plan.model.accounts.first { $0.name == "Revenue" })

        XCTAssertEqual(revenue.sheet, "Forecast")
    }

    /// Provenance is not the name. An account knows its sheet whether or not
    /// anything made it necessary to say so.
    func testASingleSheetWorkbookNamesAccountsBare() throws {
        let workbook = Workbook()
        addSheet(workbook, named: "Forecast", rows: [("Revenue", 1_000), ("Cost", 400)])

        let plan = ExcelRecognizer.recognize(workbook)

        XCTAssertEqual(
            Set(plan.model.accounts.map(\.name)), ["Revenue", "Cost"],
            "no qualification where nothing is ambiguous. Got: \(plan.model.accounts.map(\.name))")
    }

    // MARK: - Recognizing the whole workbook

    func testEverySheetWithATimelineContributes() throws {
        let workbook = Workbook()
        addSheet(workbook, named: "Data", rows: [("Units", 10)])
        addSheet(workbook, named: "Calc", rows: [("Price", 5)])

        let plan = ExcelRecognizer.recognize(workbook)

        XCTAssertEqual(Set(plan.model.accounts.map(\.name)), ["Units", "Price"])
        XCTAssertEqual(
            Set(plan.model.accounts.compactMap(\.sheet)), ["Data", "Calc"],
            "and each remembers which sheet it came from")
    }

    /// Both sides get qualified, not just the second one found.
    ///
    /// Qualifying only the later would make which sheet keeps the bare name depend
    /// on the order sheets happen to sit in the workbook — a name that changes when
    /// somebody drags a tab.
    func testANameOnTwoSheetsIsQualifiedOnBoth() throws {
        let workbook = Workbook()
        addSheet(workbook, named: "Paid", rows: [("Revenue", 1_000)])
        addSheet(workbook, named: "Display", rows: [("Revenue", 2_000)])

        let plan = ExcelRecognizer.recognize(workbook)

        XCTAssertEqual(
            Set(plan.model.accounts.map(\.name)), ["Paid!Revenue", "Display!Revenue"],
            "Got: \(plan.model.accounts.map(\.name))")
        XCTAssertTrue(
            plan.diagnostics.contains { $0.code == .duplicateAccountName },
            "and it is reported, because one name meaning two things is worth seeing")
    }

    func testANameOnOneSheetStaysBareEvenAlongsideACollision() throws {
        let workbook = Workbook()
        addSheet(workbook, named: "Paid", rows: [("Revenue", 1_000), ("Clicks", 50)])
        addSheet(workbook, named: "Display", rows: [("Revenue", 2_000)])

        let plan = ExcelRecognizer.recognize(workbook)

        XCTAssertTrue(
            plan.model.accounts.contains { $0.name == "Clicks" },
            "only what collides is qualified. Got: \(plan.model.accounts.map(\.name))")
    }

    // MARK: - Sheets that are not models

    func testASheetWithNoTimelineContributesNothingAndIsNotAnError() throws {
        let workbook = Workbook()
        addSheet(workbook, named: "Forecast", rows: [("Revenue", 1_000)])
        let notes = workbook.addSheet(name: "Notes")
        notes.write("Assumptions were agreed in March.", to: "A1")
        notes.write("Reviewed by the desk.", to: "A2")

        let plan = ExcelRecognizer.recognize(workbook)

        XCTAssertEqual(plan.model.accounts.map(\.name), ["Revenue"])
        XCTAssertFalse(
            plan.diagnostics.contains { $0.severity == .error },
            "a page of prose in a workbook is not a failure of the workbook. Got: "
                + "\(plan.diagnostics.map(\.code.rawValue))")
    }

    func testAWorkbookWithNoModelAtAllYieldsNoAccounts() throws {
        let workbook = Workbook()
        let notes = workbook.addSheet(name: "Notes")
        notes.write("Nothing here.", to: "A1")

        let plan = ExcelRecognizer.recognize(workbook)
        XCTAssertTrue(plan.model.accounts.isEmpty)
        XCTAssertTrue(plan.model.periods.isEmpty)
    }

    // MARK: - The timeline

    /// Sheets sharing a timeline share it. A model spanning sheets has one.
    func testSheetsShareOneTimeline() throws {
        let workbook = Workbook()
        addSheet(workbook, named: "Data", rows: [("Units", 10)])
        addSheet(workbook, named: "Calc", rows: [("Price", 5)])

        let plan = ExcelRecognizer.recognize(workbook)

        XCTAssertEqual(plan.model.periods.count, 3)
        XCTAssertEqual(plan.model.periods.first, Period.year(2024))
    }

    /// Coverage is over the whole workbook, so a sheet nobody could read counts
    /// against it rather than being quietly left out of the denominator.
    func testCoverageSpansTheWorkbook() throws {
        let workbook = Workbook()
        addSheet(workbook, named: "Forecast", rows: [("Revenue", 1_000)])
        let notes = workbook.addSheet(name: "Notes")
        notes.write("Nothing recognizable.", to: "A1")

        let plan = ExcelRecognizer.recognize(workbook)

        XCTAssertGreaterThan(plan.coverage.populatedCells, 4, "the notes cell is counted too")
        XCTAssertLessThan(
            plan.coverage.recognizedCells, plan.coverage.populatedCells,
            "and it is not recognized, so coverage says so")
    }

    // MARK: - A reference crossing a sheet

    /// The convention a large media model applies metric by metric: a `- Data`
    /// sheet holding figures, and an `- Input+Calc` sheet whose formulas read it.
    private func dataAndCalc() -> Workbook {
        let workbook = Workbook()

        let data = workbook.addSheet(name: "Cost - Data")
        for (column, year) in zip(["C", "D", "E"], ["2024", "2025", "2026"]) {
            data.write(year, to: "\(column)1")
        }
        data.write("Spend", to: "A2")
        for (column, value) in zip(["C", "D", "E"], [100.0, 110.0, 120.0]) {
            data.write(value, to: "\(column)2")
        }

        let calc = workbook.addSheet(name: "Cost - Input+Calc")
        for (column, year) in zip(["C", "D", "E"], ["2024", "2025", "2026"]) {
            calc.write(year, to: "\(column)1")
        }
        calc.write("Uplift", to: "A2")
        for column in ["C", "D", "E"] { calc.write(1.2, to: "\(column)2") }
        calc.write("Adjusted Spend", to: "A3")
        for column in ["C", "D", "E"] {
            calc.write(
                FormulaAST.multiply(
                    .sheetRef(SheetReference(sheet: "Cost - Data", cell: CellRef("\(column)2"))),
                    .cellRef(CellRef("\(column)2"))),
                to: "\(column)3")
        }
        return workbook
    }

    /// Without this the calculation sheet recovers nothing: every formula on it
    /// reaches off the sheet, and an unresolvable reference sends the whole row to
    /// residue. A hundred sheets of that is a hundred disconnected islands.
    func testAReferenceToAnotherSheetResolves() throws {
        let plan = ExcelRecognizer.recognize(dataAndCalc())

        let adjusted = try XCTUnwrap(
            plan.model.accounts.first { $0.name.hasSuffix("Adjusted Spend") },
            "Got: \(plan.model.accounts.map(\.name))")

        XCTAssertEqual(
            adjusted.formula, "([Cost - Data!Spend] * Uplift)",
            "the foreign account by its qualified name, the local one bare")
    }

    /// An account something off-sheet reads is qualified, whether or not its name
    /// collides — a reference has to name one account, and `Spend` alone would
    /// stop meaning `Cost - Data`'s the moment another sheet grew one.
    func testAnExternallyReferencedAccountIsQualified() throws {
        let plan = ExcelRecognizer.recognize(dataAndCalc())

        XCTAssertTrue(
            plan.model.accounts.contains { $0.name == "Cost - Data!Spend" },
            "Got: \(plan.model.accounts.map(\.name))")
        XCTAssertTrue(
            plan.model.accounts.contains { $0.name == "Uplift" },
            "and an account nothing off-sheet reads stays bare")
    }

    /// The model runs across the sheet boundary.
    func testTheCrossSheetModelMaterializesAndRuns() throws {
        let plan = ExcelRecognizer.recognize(dataAndCalc())
        let built = try ModelMaterializer.build(from: plan.model)
        let results = try built.definition.solve()

        let adjusted = try XCTUnwrap(results["Cost - Input+Calc!Adjusted Spend"]
            ?? results["Adjusted Spend"])
        XCTAssertEqual(adjusted[Period.year(2024)] ?? .nan, 120, accuracy: 1e-9)
        XCTAssertEqual(adjusted[Period.year(2026)] ?? .nan, 144, accuracy: 1e-9)
    }

    /// A reference to a sheet the model does not hold is still refused, and says
    /// which sheet — a missing page is a fact worth reporting, not a zero.
    func testAReferenceToASheetOutsideTheModelIsRefused() throws {
        let workbook = Workbook()
        let sheet = workbook.addSheet(name: "Calc")
        for (column, year) in zip(["C", "D", "E"], ["2024", "2025", "2026"]) {
            sheet.write(year, to: "\(column)1")
        }
        sheet.write("Reads Away", to: "A2")
        // Filled across, so the row is uniform and reaches the cross-sheet check
        // rather than being refused as disagreeing with itself first.
        for column in ["C", "D", "E"] {
            sheet.write(
                FormulaAST.sheetRef(
                    SheetReference(sheet: "Absent", cell: CellRef("\(column)9"))),
                to: "\(column)2")
        }

        let plan = ExcelRecognizer.recognize(workbook)

        XCTAssertTrue(
            plan.model.residue.contains { $0.label == "Reads Away" },
            "Got residue: \(plan.model.residue.map(\.label))")
        let reported = plan.diagnostics.first { $0.code == .crossSheetReference }
        XCTAssertNotNil(reported, "Got: \(plan.diagnostics.map(\.code.rawValue))")
        XCTAssertTrue(
            reported?.message.contains("Absent") ?? false,
            "the sheet is named. Got: \(reported?.message ?? "")")
    }

    /// Recognizing one sheet alone still refuses a reference off it — there is
    /// nothing to resolve against, and guessing would invent an account.
    func testASheetReadAloneStillRefusesAForeignReference() throws {
        let workbook = dataAndCalc()
        let calc = try XCTUnwrap(workbook.sheets.first { $0.name == "Cost - Input+Calc" })

        let plan = ExcelRecognizer.recognize(calc, in: workbook)

        XCTAssertTrue(
            plan.model.residue.contains { $0.label == "Adjusted Spend" },
            "Got: \(plan.model.residue.map(\.label))")
    }
}
