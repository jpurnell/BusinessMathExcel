import Foundation
import Testing
@testable import BusinessMathExcel
import BusinessMath
import SwiftXLSX

/// Turning a plan into something that runs.
///
/// The division of labour: recognition is best-effort and never throws, so a
/// workbook that half-fits still yields a readable plan. Materialization is the
/// opposite — it validates and **throws**, because a `ModelDefinition` built from
/// a plan with a hole in it would run and produce numbers.
@Suite struct ModelMaterializerTests {

    private let years = [Period.year(2024), Period.year(2025), Period.year(2026)]

    private func recognize(_ build: (Worksheet) -> Void) throws -> RecognizedModel {
        let wb = Workbook()
        let sheet = wb.addSheet(name: "Model")
        sheet.write("2024", to: "C1")
        sheet.write("2025", to: "D1")
        sheet.write("2026", to: "E1")
        build(sheet)
        return ExcelRecognizer.recognize(try #require(wb.sheets.first)).model
    }

    // MARK: - Materializing

    @Test func aPlanBecomesAModelThatEvaluates() throws {
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
        #expect(results["Profit"]?.valuesArray == [60, 70, 80])
    }

    @Test func suppliedAccountsBecomeInputs() throws {
        let plan = try recognize { sheet in
            sheet.write("Revenue", to: "A2")
            sheet.write(100.0, to: "C2")
            sheet.write(110.0, to: "D2")
            sheet.write(121.0, to: "E2")
        }

        let built = try ModelMaterializer.build(from: plan)
        #expect(built.definition.inputs["Revenue"]?.valuesArray == [100, 110, 121])
    }

    // MARK: - Refusals

    @Test func aDuplicateAccountIsRefused() {
        let plan = RecognizedModel(
            periods: years,
            accounts: [
                RecognizedAccount(name: "Revenue", values: [years[0]: 1], provenance: [CellRef("C2")]),
                RecognizedAccount(name: "Revenue", values: [years[0]: 2], provenance: [CellRef("C3")])
            ],
            rollforwards: [],
            residue: []
        )

        if let error = #expect(throws: (any Error).self, performing: { try ModelMaterializer.build(from: plan) }) {
            #expect(error as? MaterializationError == .duplicateAccount("Revenue"))
        }
    }

    @Test func aFormulaReadingAnAccountThatDoesNotExistIsRefused() {
        let plan = RecognizedModel(
            periods: years,
            accounts: [
                RecognizedAccount(
                    name: "Profit", formula: "Revenue - Cost", provenance: [CellRef("C4")])
            ],
            rollforwards: [],
            residue: []
        )

        if let error = #expect(throws: (any Error).self, performing: { try ModelMaterializer.build(from: plan) }) {
            guard case .unresolvedReference(let account, _)? = error as? MaterializationError else {
                Issue.record("Expected an unresolved reference, got \(error)"); return
            }
            #expect(account == "Profit")
        }
    }

    @Test func theUnresolvedErrorNamesWhatWasMissing() {
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

        if let error = #expect(throws: (any Error).self, performing: { try ModelMaterializer.build(from: plan) }) {
            guard case .unresolvedReference(_, let missing)? = error as? MaterializationError else {
                Issue.record("Expected an unresolved reference, got \(error)"); return
            }
            #expect(missing == "Revenue", "so the gap is actionable, not just reported")
        }
    }

    @Test func anUnparseableFormulaIsRefused() {
        let plan = RecognizedModel(
            periods: years,
            accounts: [
                RecognizedAccount(name: "Broken", formula: "1 +", provenance: [CellRef("C2")])
            ],
            rollforwards: [],
            residue: []
        )

        if let error = #expect(throws: (any Error).self, performing: { try ModelMaterializer.build(from: plan) }) {
            guard case .invalidFormula(let account, _)? = error as? MaterializationError else {
                Issue.record("Expected an invalid formula, got \(error)"); return
            }
            #expect(account == "Broken")
        }
    }

    @Test func residueIsNotMaterialized() throws {
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
        #expect(built.definition.inputs["Looked up"] == nil)
        #expect(built.definition.formula(for: "Looked up") == nil)
        #expect(!plan.residue.isEmpty, "and it is still recorded as residue")
    }

    // MARK: - Rollforwards

    @Test func aCarryBecomesARollforwardWithItsSeed() throws {
        let plan = try recognize { sheet in
            sheet.write("Revenue", to: "A2")
            sheet.write(100.0, to: "C2")
            sheet.write(FormulaAST.multiply(.cellRef(CellRef("C2")), .number(1.1)), to: "D2")
            sheet.write(FormulaAST.multiply(.cellRef(CellRef("D2")), .number(1.1)), to: "E2")
        }

        let built = try ModelMaterializer.build(from: plan)
        let carry = try #require(built.rollforwards.first)
        #expect(carry.seed == 100, "seeded from the first period's own cell")
        // The row grows off itself, so its printed values are the openings and the
        // formula computes the close. Naming these the other way round evaluates
        // cleanly and reports every period one step early — see GoldenPathTests.
        #expect(carry.opening == "Revenue")
        #expect(carry.closing == "Revenue Closing")
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
    @Test func whatCannotResolveIsDroppedAndNamed() throws {
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

        #expect(pruned.dropped.map(\.label) == ["Exit"])
        #expect(pruned.dropped.first?.reason == .unresolvedReference)
        #expect(pruned.model.definition.formula(for: "Doubled") == "(Revenue * 2.0)", "the rest still builds")

        let evaluated = try PeriodDriver(
            definition: pruned.model.definition, rollforwards: pruned.model.rollforwards
        ).run(over: pruned.model.periods)
        #expect(evaluated["Doubled"]?.valuesArray == [200, 200, 200])
    }

    @Test func droppingIsTransitive() throws {
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
        #expect(pruned.dropped.map(\.label).sorted() == ["Equity", "Exit"], "a model built on a dropped account is not a model")
    }

    @Test func aWholeModelDropsNothing() throws {
        let plan = try recognize { sheet in
            sheet.write("Revenue", to: "A2")
            for column in ["C", "D", "E"] { sheet.write(100.0, to: "\(column)2") }
        }

        let pruned = try ModelMaterializer.buildResolvable(from: plan)
        #expect(pruned.dropped.isEmpty)
    }
}
