import XCTest
@testable import BusinessMathExcel
import BusinessMath
import SwiftXLSX

/// A recognized formula, before it becomes text.
///
/// The equivalence that matters here is not tested in this file. It is tested by
/// every other formula assertion in the suite: the string a `Split` reports is now
/// *rendered from* this tree rather than built alongside it, so those tests
/// continuing to pass unchanged is what says the refactor preserved behaviour.
///
/// What is tested here is the tree's own contract — that it renders what the
/// grammar expects, and that operations on it work structurally rather than by
/// text substitution.
final class RecognizedExpressionTests: XCTestCase {

    private let revenue = RecognizedExpression.account("Revenue")
    private let cost = RecognizedExpression.account("Cost")

    // MARK: - Rendering

    func testAnAccountRendersBracketedWhenItNeedsToBe() {
        XCTAssertEqual(RecognizedExpression.account("Revenue").rendered(), "Revenue")
        XCTAssertEqual(
            RecognizedExpression.account("Sales & Marketing").rendered(),
            "[Sales & Marketing]",
            "the grammar reads & as an operator, so an unbracketed name arrives as three tokens"
        )
        XCTAssertEqual(RecognizedExpression.account("A/P").rendered(), "[A/P]")
        XCTAssertEqual(
            RecognizedExpression.account("2023 Revenue").rendered(), "[2023 Revenue]",
            "a leading digit would read as a number"
        )
    }

    func testBinaryOperatorsRenderParenthesised() {
        XCTAssertEqual(
            RecognizedExpression.binary(.multiply, revenue, cost).rendered(),
            "(Revenue * Cost)")
        XCTAssertEqual(
            RecognizedExpression.binary(.notEqual, revenue, cost).rendered(),
            "(Revenue <> Cost)")
    }

    func testNestingRendersItsOwnParentheses() {
        let inner = RecognizedExpression.binary(.subtract, revenue, cost)
        let outer = RecognizedExpression.binary(.multiply, inner, .number(0.4))
        XCTAssertEqual(outer.rendered(), "((Revenue - Cost) * 0.4)")
    }

    /// A range reaches a function as several arguments, not one.
    func testAListFlattensIntoACallsArguments() {
        let range = RecognizedExpression.list([revenue, cost, .account("Tax")])
        XCTAssertEqual(
            RecognizedExpression.call("SUM", [range]).rendered(),
            "SUM(Revenue, Cost, Tax)")
    }

    func testARefusalRendersAsAPlaceholder() {
        XCTAssertEqual(
            RecognizedExpression.refused.rendered(), "0",
            "a placeholder standing where a formula would have been — the account "
                + "carrying it goes to residue, so the zero is never evaluated"
        )
    }

    // MARK: - Reading the tree

    func testAccountsAreListedInReadingOrder() {
        let expression = RecognizedExpression.binary(
            .add,
            .binary(.multiply, revenue, .account("Margin")),
            .negated(cost))
        XCTAssertEqual(expression.accounts, ["Revenue", "Margin", "Cost"])
    }

    func testLiteralsReadNoAccounts() {
        XCTAssertEqual(RecognizedExpression.number(42).accounts, [])
        XCTAssertEqual(RecognizedExpression.refused.accounts, [])
    }

    func testComparisonsAreDistinguishedFromArithmetic() {
        XCTAssertFalse(RecognizedExpression.Operator.multiply.isComparison)
        XCTAssertTrue(RecognizedExpression.Operator.greaterOrEqual.isComparison)
    }

    // MARK: - Renaming

    /// Renaming structurally, not textually — which is the reason the tree exists
    /// at this point in the pipeline rather than only at the end of it.
    func testRenamingMatchesWholeAccountsOnly() {
        let expression = RecognizedExpression.binary(
            .add, .account("Debt"), .account("Debt Service"))
        let renamed = expression.renaming("Debt", to: "Opening Debt")

        XCTAssertEqual(renamed.accounts, ["Opening Debt", "Debt Service"])
        XCTAssertEqual(
            renamed.rendered(), "([Opening Debt] + [Debt Service])",
            "a string replacement would have rewritten the inside of `Debt Service` too"
        )
    }

    func testRenamingReachesEveryBranch() {
        let expression = RecognizedExpression.call(
            "SUM",
            [.list([.account("X"), .negated(.account("X"))]),
             .binary(.divide, .account("X"), .number(2))])
        XCTAssertEqual(expression.renaming("X", to: "Y").accounts, ["Y", "Y", "Y"])
    }

    // MARK: - Through recognition

    /// The tree reaches the account, and agrees with the string beside it.
    func testARecognizedAccountCarriesBothFormAndAgrees() throws {
        let workbook = Workbook()
        let sheet = workbook.addSheet(name: "Model")
        sheet.write("2024", to: "C1")
        sheet.write("2025", to: "D1")
        sheet.write("2026", to: "E1")
        sheet.write("Revenue", to: "A2")
        sheet.write("Margin", to: "A3")
        sheet.write("EBITDA", to: "A4")
        for column in ["C", "D", "E"] {
            sheet.write(1_000.0, to: "\(column)2")
            sheet.write(0.4, to: "\(column)3")
            sheet.write(
                FormulaAST.multiply(
                    .cellRef(CellRef("\(column)2")), .cellRef(CellRef("\(column)3"))),
                to: "\(column)4")
        }

        let plan = ExcelRecognizer.recognize(try XCTUnwrap(workbook.sheets.first))
        let ebitda = try XCTUnwrap(plan.model.accounts.first { $0.name == "EBITDA" })

        let expression = try XCTUnwrap(ebitda.expression)
        XCTAssertEqual(expression, .binary(.multiply, .account("Revenue"), .account("Margin")))
        XCTAssertEqual(
            expression.rendered(), ebitda.formula,
            "the string is rendered from the tree, so they cannot disagree"
        )
    }

    func testAnInputAccountHasNoExpression() throws {
        let workbook = Workbook()
        let sheet = workbook.addSheet(name: "Model")
        sheet.write("2024", to: "C1")
        sheet.write("2025", to: "D1")
        sheet.write("2026", to: "E1")
        sheet.write("Revenue", to: "A2")
        for column in ["C", "D", "E"] { sheet.write(1_000.0, to: "\(column)2") }

        let plan = ExcelRecognizer.recognize(try XCTUnwrap(workbook.sheets.first))
        let revenue = try XCTUnwrap(plan.model.accounts.first { $0.name == "Revenue" })

        XCTAssertNil(revenue.expression, "data has no rule")
        XCTAssertNil(revenue.formula)
    }
}
