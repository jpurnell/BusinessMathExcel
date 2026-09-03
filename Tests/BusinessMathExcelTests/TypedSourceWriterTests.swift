import XCTest
@testable import BusinessMathExcel
import BusinessMath
import SwiftXLSX

/// Emitting a recognized workbook as Swift source.
///
/// A recognized plan can already be materialized and run, which is the right
/// answer for a tool and the wrong one for a person: a person wants to read what
/// the sheet said, keep it under version control, and have a compiler check it.
///
/// The bar is therefore not "looks plausible". Emitted source that does not
/// compile is worse than none, so every rule here exists to keep the writer from
/// producing something the build would reject — and where it cannot be sure, it
/// emits the untyped spelling rather than guessing at a unit.
final class TypedSourceWriterTests: XCTestCase {

    private func account(
        _ name: String,
        _ expression: RecognizedExpression,
        unit: UnitKind?,
        at cell: String = "A1"
    ) -> RecognizedAccount {
        RecognizedAccount(
            name: name, expression: expression, unit: unit, provenance: [CellRef(cell)])
    }

    private func input(
        _ name: String, _ values: [Double], unit: UnitKind?, at cell: String = "A1"
    ) -> RecognizedAccount {
        var byPeriod: [Period: Double] = [:]
        for (index, value) in values.enumerated() {
            byPeriod[Period.year(2024 + index)] = value
        }
        return RecognizedAccount(
            name: name, values: byPeriod, unit: unit, provenance: [CellRef(cell)])
    }

    private func plan(
        _ accounts: [RecognizedAccount],
        rollforwards: [LagDecomposition.RecognizedRollforward] = [],
        periods: Int = 2
    ) -> RecognizedModel {
        RecognizedModel(
            periods: (0..<periods).map { Period.year(2024 + $0) },
            accounts: accounts,
            rollforwards: rollforwards,
            residue: []
        )
    }

    // MARK: - Typed declarations

    func testAnAccountWithAKnownUnitIsDeclaredTyped() {
        let source = TypedSourceWriter.swiftSource(
            for: plan([
                input("Revenue", [1_000, 1_150], unit: .money, at: "C6"),
                input("Margin", [0.4, 0.4], unit: .ratio, at: "C7"),
                account("EBITDA",
                        .binary(.multiply, .account("Revenue"), .account("Margin")),
                        unit: .money, at: "C8"),
            ]),
            sheetName: "Model")

        XCTAssertTrue(
            source.contains(#"let revenue = LineItem<Money>("Revenue")"#),
            "Got:\n\(source)")
        XCTAssertTrue(source.contains(#"let margin = LineItem<Ratio>("Margin")"#))
        XCTAssertTrue(source.contains("revenue.expr * margin.expr"))
    }

    /// `Count` upstream, not `Duration` — the standard library owns that name, so
    /// BusinessMath renamed the unit and the writer must emit what compiles.
    func testTheDurationUnitEmitsAsCount() {
        let source = TypedSourceWriter.swiftSource(
            for: plan([input("Years", [5], unit: .duration, at: "D22")]),
            sheetName: "Model")

        XCTAssertTrue(source.contains(#"LineItem<Count>("Years")"#), "Got:\n\(source)")
        XCTAssertFalse(source.contains("Duration"))
    }

    func testEveryDeclarationCarriesItsProvenance() {
        let source = TypedSourceWriter.swiftSource(
            for: plan([input("Revenue", [1_000], unit: .money, at: "E30")]),
            sheetName: "ANSWER KEY")

        XCTAssertTrue(
            source.contains("// ANSWER KEY!E30"),
            "the only way to check the recognizer's work against the workbook by hand"
        )
    }

    // MARK: - Untyped fallback

    /// Sixteen of the Wharton sheet's 46 accounts state no unit, so this is the
    /// common case on real input rather than a corner.
    func testAnAccountWithNoUnitEmitsTheStringAPI() {
        let source = TypedSourceWriter.swiftSource(
            for: plan([
                input("Total FCF", [10], unit: nil, at: "E47"),
                account("Doubled", .binary(.multiply, .account("Total FCF"), .number(2)),
                        unit: nil, at: "E48"),
            ]),
            sheetName: "Model")

        XCTAssertFalse(
            source.contains("LineItem"),
            "LineItem<U> has no untyped form, and picking a unit would be inventing one"
        )
        XCTAssertTrue(
            source.contains(#".defining("Doubled", as: "([Total FCF] * 2.0)")"#),
            "Got:\n\(source)")
    }

    /// A definition reading one typed and one untyped account cannot be written
    /// typed, because there is no `Expr` for the untyped side.
    func testAMixedExpressionEmitsUntypedWhole() {
        let source = TypedSourceWriter.swiftSource(
            for: plan([
                input("Revenue", [1_000], unit: .money, at: "C6"),
                input("Mystery", [1], unit: nil, at: "C7"),
                account("Total", .binary(.add, .account("Revenue"), .account("Mystery")),
                        unit: .money, at: "C8"),
            ]),
            sheetName: "Model")

        XCTAssertTrue(
            source.contains(#".defining("Total", as: "(Revenue + Mystery)")"#),
            "emitted whole rather than half-cast into something that would not compile. "
                + "Got:\n\(source)")
        XCTAssertTrue(
            source.contains(#"let revenue = LineItem<Money>("Revenue")"#),
            "and the typed handle still exists for anything that can use it")
    }

    /// The typed algebra has no comparison operators and no `IF`.
    func testAComparisonEmitsUntyped() {
        let source = TypedSourceWriter.swiftSource(
            for: plan([
                input("Cash", [10], unit: .money, at: "C6"),
                input("Debt", [5], unit: .money, at: "C7"),
                account("Covered", .binary(.greaterThan, .account("Cash"), .account("Debt")),
                        unit: .ratio, at: "C8"),
            ]),
            sheetName: "Model")

        XCTAssertTrue(source.contains(#".defining("Covered", as:"#), "Got:\n\(source)")
    }

    /// `MIN`, `MAX` and `ABS` exist in the typed layer. Nothing else does.
    func testOnlyTheTypedFunctionsEmitTyped() {
        let plan = plan([
            input("Cash", [10], unit: .money, at: "C6"),
            input("Debt", [5], unit: .money, at: "C7"),
            account("Sweep", .call("MIN", [.account("Cash"), .account("Debt")]),
                    unit: .money, at: "C8"),
            account("Total", .call("SUM", [.list([.account("Cash"), .account("Debt")])]),
                    unit: .money, at: "C9"),
        ])
        let source = TypedSourceWriter.swiftSource(for: plan, sheetName: "Model")

        XCTAssertTrue(source.contains("min(cash.expr, debt.expr)"), "Got:\n\(source)")
        XCTAssertTrue(source.contains(#".defining("Total", as: "SUM(Cash, Debt)")"#))
    }

    /// An illegal combination cannot be emitted typed, because it would not build.
    func testAnExpressionTheAlgebraRejectsEmitsUntyped() {
        let source = TypedSourceWriter.swiftSource(
            for: plan([
                input("Revenue", [1_000], unit: .money, at: "C6"),
                input("Margin", [0.4], unit: .ratio, at: "C7"),
                // Money + Ratio has no overload upstream.
                account("Nonsense", .binary(.add, .account("Revenue"), .account("Margin")),
                        unit: .money, at: "C8"),
            ]),
            sheetName: "Model")

        XCTAssertTrue(source.contains(#".defining("Nonsense", as:"#), "Got:\n\(source)")
        XCTAssertFalse(source.contains("revenue.expr + margin.expr"))
    }

    // MARK: - Literals

    /// A bare number is dimensionless unless that will not compile. A rate would
    /// be a claim about periodicity the sheet never made.
    func testABareNumberIsARatio() {
        let source = TypedSourceWriter.swiftSource(
            for: plan([
                input("Revenue", [1_000], unit: .money, at: "C6"),
                account("Grown", .binary(.multiply, .account("Revenue"), .number(1.15)),
                        unit: .money, at: "C7"),
            ]),
            sheetName: "Model")

        XCTAssertTrue(source.contains("revenue.expr * ratio(1.15)"), "Got:\n\(source)")
    }

    // MARK: - A runnable file

    func testTheFileIsRunnableRatherThanAFragment() {
        let source = TypedSourceWriter.swiftSource(
            for: plan(
                [
                    input("Revenue", [1_000, 1_150], unit: .money, at: "C6"),
                    account("Closing", .account("Revenue"), unit: .money, at: "C7"),
                ],
                rollforwards: [
                    LagDecomposition.RecognizedRollforward(
                        opening: "Opening", closing: "Closing",
                        seedCell: CellRef("B7"), seed: 100)
                ]),
            sheetName: "Model")

        XCTAssertTrue(source.contains("import BusinessMath"), "Got:\n\(source)")
        XCTAssertTrue(source.contains("Period.year(2024)"), "the timeline")
        XCTAssertTrue(source.contains("TimeSeries(periods:"), "the data")
        XCTAssertTrue(
            source.contains(#"Rollforward(opening: "Opening", closing: "Closing", seed: 100.0)"#),
            "the carries")
        XCTAssertTrue(source.contains("try model.validateUnits()"))
        XCTAssertTrue(
            source.contains("enum ImportedModel {"),
            "an enum of static members, not top-level code — top-level statements "
                + "are legal only in main.swift, so a file of them cannot be compiled "
                + "into the library or test target where a generated model belongs")
    }

    /// An opening balance is the closing balance at another moment, so it has the
    /// same unit — and nothing in the plan declares it, because the driver supplies
    /// it. Without this, every definition reading an opening balance falls untyped,
    /// which on a debt schedule is most of them.
    func testARollforwardsOpeningAccountInheritsItsClosingUnit() {
        let source = TypedSourceWriter.swiftSource(
            for: plan(
                [
                    input("Rate", [0.1], unit: .rate, at: "D8"),
                    account("Closing Debt",
                            .binary(.multiply, .account("Opening Debt"), .account("Rate")),
                            unit: .money, at: "E52"),
                ],
                rollforwards: [
                    LagDecomposition.RecognizedRollforward(
                        opening: "Opening Debt", closing: "Closing Debt",
                        seedCell: CellRef("D52"), seed: 100)
                ]),
            sheetName: "Model")

        XCTAssertTrue(
            source.contains(#"let openingDebt = LineItem<Money>("Opening Debt")"#),
            "Got:\n\(source)")
        XCTAssertTrue(
            source.contains("openingDebt.expr * rate.expr"),
            "and the definition reading it is typed rather than falling back")
    }

    // MARK: - Names

    func testNamesBecomeLegalSwiftIdentifiers() {
        let source = TypedSourceWriter.swiftSource(
            for: plan([
                input("EBITDA margin", [0.4], unit: .ratio, at: "C6"),
                input("Less: Interest", [10], unit: .money, at: "C7"),
                input("2023 Revenue", [100], unit: .money, at: "C8"),
            ]),
            sheetName: "Model")

        XCTAssertTrue(source.contains("let ebitdaMargin ="), "Got:\n\(source)")
        XCTAssertTrue(source.contains("let lessInterest ="))
        XCTAssertTrue(
            source.contains("let revenue2023 ="),
            "a leading digit is not a legal identifier, and the year still belongs in the name")
    }

    func testNamesThatCollideAreDistinguished() {
        let source = TypedSourceWriter.swiftSource(
            for: plan([
                input("Interest", [10], unit: .money, at: "C6"),
                input("interest", [11], unit: .money, at: "C7"),
            ]),
            sheetName: "Model")

        XCTAssertTrue(source.contains("let interest ="), "Got:\n\(source)")
        XCTAssertTrue(
            source.contains("let interest2 ="),
            "two accounts differing only in case are one Swift identifier, and both must exist")
    }

    /// A model name that is already a legal identifier keeps the caller's casing.
    ///
    /// Running it through the account-name path would flatten it: `GoldenForecast`
    /// has no separators to split on, so it came back as one lowercased word and
    /// the emitted namespace did not match what the caller asked for.
    func testAModelNameKeepsItsOwnCasing() {
        let source = TypedSourceWriter.swiftSource(
            for: plan([input("Revenue", [1], unit: .money, at: "C6")]),
            sheetName: "Model", modelName: "GoldenForecast")

        XCTAssertTrue(source.contains("enum GoldenForecast {"), "Got:\n\(source)")
    }

    func testAModelNameThatIsNotAnIdentifierIsMadeIntoOne() {
        let source = TypedSourceWriter.swiftSource(
            for: plan([input("Revenue", [1], unit: .money, at: "C6")]),
            sheetName: "Model", modelName: "ANSWER KEY")

        XCTAssertTrue(source.contains("enum AnswerKey {"), "Got:\n\(source)")
    }

    func testAKeywordIsEscaped() {
        let source = TypedSourceWriter.swiftSource(
            for: plan([input("Return", [10], unit: .money, at: "C6")]),
            sheetName: "Model")

        XCTAssertTrue(source.contains("let `return` ="), "Got:\n\(source)")
    }
}
