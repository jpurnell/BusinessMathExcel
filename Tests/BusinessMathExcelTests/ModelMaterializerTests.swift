import XCTest
@testable import BusinessMathExcel
import BusinessMath
import SwiftXLSX

/// Turning a plan into something that runs.
///
/// The division of labour: recognition is best-effort and never throws, so a
/// workbook that half-fits still yields a readable plan. Materialization is the
/// opposite — it validates and **throws**, because a `ModelDefinition` built from
/// a plan with a hole in it would run and produce numbers.
final class ModelMaterializerTests: XCTestCase {

    private let years = [Period.year(2024), Period.year(2025), Period.year(2026)]

    private func recognize(_ build: (Worksheet) -> Void) throws -> RecognizedModel {
        let wb = Workbook()
        let sheet = wb.addSheet(name: "Model")
        sheet.write("2024", to: "C1")
        sheet.write("2025", to: "D1")
        sheet.write("2026", to: "E1")
        build(sheet)
        return ExcelRecognizer.recognize(try XCTUnwrap(wb.sheets.first)).model
    }

    // MARK: - Materializing

    func testAPlanBecomesAModelThatEvaluates() throws {
        let plan = try recognize { sheet in
            sheet.write("Revenue", to: "A2")
            sheet.write("Cost", to: "A3")
            sheet.write("Profit", to: "A4")
            for (index, column) in ["C", "D", "E"].enumerated() {
                sheet.write(Double(100 + index * 10), to: "\(column)2")
                sheet.write(40.0, to: "\(column)3")
                sheet.write(
                    FormulaAST.subtract(
                        .cellRef(CellRef("\(column)2")), .cellRef(CellRef("\(column)3"))),
                    to: "\(column)4")
            }
        }

        let built = try ModelMaterializer.build(from: plan)
        let results = try built.definition.evaluate()
        XCTAssertEqual(results["Profit"]?.valuesArray, [60, 70, 80])
    }

    func testSuppliedAccountsBecomeInputs() throws {
        let plan = try recognize { sheet in
            sheet.write("Revenue", to: "A2")
            sheet.write(100.0, to: "C2")
            sheet.write(110.0, to: "D2")
            sheet.write(121.0, to: "E2")
        }

        let built = try ModelMaterializer.build(from: plan)
        XCTAssertEqual(built.definition.inputs["Revenue"]?.valuesArray, [100, 110, 121])
    }

    // MARK: - Refusals

    func testADuplicateAccountIsRefused() {
        let plan = RecognizedModel(
            periods: years,
            accounts: [
                RecognizedAccount(name: "Revenue", values: [years[0]: 1], provenance: [CellRef("C2")]),
                RecognizedAccount(name: "Revenue", values: [years[0]: 2], provenance: [CellRef("C3")])
            ],
            rollforwards: [],
            residue: []
        )

        XCTAssertThrowsError(try ModelMaterializer.build(from: plan)) { error in
            XCTAssertEqual(error as? MaterializationError, .duplicateAccount("Revenue"))
        }
    }

    func testAFormulaReadingAnAccountThatDoesNotExistIsRefused() {
        let plan = RecognizedModel(
            periods: years,
            accounts: [
                RecognizedAccount(
                    name: "Profit", formula: "Revenue - Cost", provenance: [CellRef("C4")])
            ],
            rollforwards: [],
            residue: []
        )

        XCTAssertThrowsError(try ModelMaterializer.build(from: plan)) { error in
            guard case .unresolvedReference(let account, _)? = error as? MaterializationError else {
                return XCTFail("Expected an unresolved reference, got \(error)")
            }
            XCTAssertEqual(account, "Profit")
        }
    }

    func testTheUnresolvedErrorNamesWhatWasMissing() {
        let plan = RecognizedModel(
            periods: years,
            accounts: [
                RecognizedAccount(name: "Cost", values: [years[0]: 40], provenance: [CellRef("C3")]),
                RecognizedAccount(
                    name: "Profit", formula: "Revenue - Cost", provenance: [CellRef("C4")])
            ],
            rollforwards: [],
            residue: []
        )

        XCTAssertThrowsError(try ModelMaterializer.build(from: plan)) { error in
            guard case .unresolvedReference(_, let missing)? = error as? MaterializationError else {
                return XCTFail("Expected an unresolved reference, got \(error)")
            }
            XCTAssertEqual(missing, "Revenue", "so the gap is actionable, not just reported")
        }
    }

    func testAnUnparseableFormulaIsRefused() {
        let plan = RecognizedModel(
            periods: years,
            accounts: [
                RecognizedAccount(name: "Broken", formula: "1 +", provenance: [CellRef("C2")])
            ],
            rollforwards: [],
            residue: []
        )

        XCTAssertThrowsError(try ModelMaterializer.build(from: plan)) { error in
            guard case .invalidFormula(let account, _)? = error as? MaterializationError else {
                return XCTFail("Expected an invalid formula, got \(error)")
            }
            XCTAssertEqual(account, "Broken")
        }
    }

    func testResidueIsNotMaterialized() throws {
        // A row we could not translate must not reappear as an account with a
        // value invented for it.
        let plan = try recognize { sheet in
            sheet.write("Revenue", to: "A2")
            sheet.write("Looked up", to: "A4")
            for column in ["C", "D", "E"] {
                sheet.write(100.0, to: "\(column)2")
                sheet.write(
                    FormulaAST.function("VLOOKUP", [.cellRef(CellRef("\(column)2"))]),
                    to: "\(column)4")
            }
        }

        let built = try ModelMaterializer.build(from: plan)
        XCTAssertNil(built.definition.inputs["Looked up"])
        XCTAssertNil(built.definition.formula(for: "Looked up"))
        XCTAssertFalse(plan.residue.isEmpty, "and it is still recorded as residue")
    }

    // MARK: - Rollforwards

    func testACarryBecomesARollforwardWithItsSeed() throws {
        let plan = try recognize { sheet in
            sheet.write("Revenue", to: "A2")
            sheet.write(100.0, to: "C2")
            sheet.write(FormulaAST.multiply(.cellRef(CellRef("C2")), .number(1.1)), to: "D2")
            sheet.write(FormulaAST.multiply(.cellRef(CellRef("D2")), .number(1.1)), to: "E2")
        }

        let built = try ModelMaterializer.build(from: plan)
        let carry = try XCTUnwrap(built.rollforwards.first)
        XCTAssertEqual(carry.seed, 100, "seeded from the first period's own cell")
        // The row grows off itself, so its printed values are the openings and the
        // formula computes the close. Naming these the other way round evaluates
        // cleanly and reports every period one step early — see GoldenPathTests.
        XCTAssertEqual(carry.opening, "Revenue")
        XCTAssertEqual(carry.closing, "Revenue Closing")
    }

    // MARK: - Building what resolves

    /// Building the part that resolves, and saying what did not.
    ///
    /// ``ModelMaterializer/build(from:)`` throws on the first hole, which is the
    /// right answer when a caller wants a model or nothing. It is the wrong answer
    /// when a caller wants to know *how much* of a workbook works: one exit-year
    /// row that cannot be expressed as a period rule stops a sheet whose income
    /// statement, cash-flow build and debt schedule are all fine.
    ///
    /// This is refusal, not repair. Nothing is filled in, guessed, or defaulted —
    /// the accounts that cannot resolve are removed and returned, and so is
    /// everything that depended on them.
    func testWhatCannotResolveIsDroppedAndNamed() throws {
        let plan = try recognize { sheet in
            sheet.write("Revenue", to: "A2")
            for column in ["C", "D", "E"] { sheet.write(100.0, to: "\(column)2") }
            sheet.write("Doubled", to: "A3")
            for column in ["C", "D", "E"] {
                sheet.write(
                    FormulaAST.multiply(.cellRef(CellRef("\(column)2")), .number(2)),
                    to: "\(column)3")
            }
        }
        // An account nothing in the plan defines.
        let holed = RecognizedModel(
            periods: plan.periods,
            accounts: plan.accounts + [
                RecognizedAccount(
                    name: "Exit", formula: "([Missing Row] * 2)", provenance: [CellRef("A9")])
            ],
            rollforwards: plan.rollforwards,
            residue: plan.residue
        )

        let pruned = try ModelMaterializer.buildResolvable(from: holed)

        XCTAssertEqual(pruned.dropped.map(\.label), ["Exit"])
        XCTAssertEqual(pruned.dropped.first?.reason, .unresolvedReference)
        XCTAssertNotNil(pruned.model.definition.formula(for: "Doubled"), "the rest still builds")

        let evaluated = try PeriodDriver(
            definition: pruned.model.definition, rollforwards: pruned.model.rollforwards
        ).run(over: pruned.model.periods)
        XCTAssertEqual(evaluated["Doubled"]?.valuesArray, [200, 200, 200])
    }

    func testDroppingIsTransitive() throws {
        let plan = try recognize { sheet in
            sheet.write("Revenue", to: "A2")
            for column in ["C", "D", "E"] { sheet.write(100.0, to: "\(column)2") }
        }
        let holed = RecognizedModel(
            periods: plan.periods,
            accounts: plan.accounts + [
                RecognizedAccount(
                    name: "Exit", formula: "([Missing Row] * 2)", provenance: [CellRef("A9")]),
                RecognizedAccount(
                    name: "Equity", formula: "(Exit + Revenue)", provenance: [CellRef("A10")]),
            ],
            rollforwards: plan.rollforwards,
            residue: plan.residue
        )

        let pruned = try ModelMaterializer.buildResolvable(from: holed)
        XCTAssertEqual(
            pruned.dropped.map(\.label).sorted(), ["Equity", "Exit"],
            "a model built on a dropped account is not a model"
        )
    }

    func testAWholeModelDropsNothing() throws {
        let plan = try recognize { sheet in
            sheet.write("Revenue", to: "A2")
            for column in ["C", "D", "E"] { sheet.write(100.0, to: "\(column)2") }
        }

        let pruned = try ModelMaterializer.buildResolvable(from: plan)
        XCTAssertTrue(pruned.dropped.isEmpty)
    }
}
