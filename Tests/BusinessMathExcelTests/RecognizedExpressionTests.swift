import Foundation
import Testing
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
@Suite struct RecognizedExpressionTests {

    private let revenue = RecognizedExpression.account("Revenue")
    private let cost = RecognizedExpression.account("Cost")

    // MARK: - Rendering

    @Test func anAccountRendersBracketedWhenItNeedsToBe() {
        #expect(RecognizedExpression.account("Revenue").rendered() == "Revenue")
        #expect(RecognizedExpression.account("Sales & Marketing").rendered() == "[Sales & Marketing]", "the grammar reads & as an operator, so an unbracketed name arrives as three tokens")
        #expect(RecognizedExpression.account("A/P").rendered() == "[A/P]")
        #expect(RecognizedExpression.account("2023 Revenue").rendered() == "[2023 Revenue]", "a leading digit would read as a number")
    }

    @Test func binaryOperatorsRenderParenthesised() {
        #expect(RecognizedExpression.binary(.multiply, revenue, cost).rendered() == "(Revenue * Cost)")
        #expect(RecognizedExpression.binary(.notEqual, revenue, cost).rendered() == "(Revenue <> Cost)")
    }

    @Test func nestingRendersItsOwnParentheses() {
        let inner = RecognizedExpression.binary(.subtract, revenue, cost)
        let outer = RecognizedExpression.binary(.multiply, inner, .number(0.4))
        #expect(outer.rendered() == "((Revenue - Cost) * 0.4)")
    }

    /// A range reaches a function as several arguments, not one.
    @Test func aListFlattensIntoACallsArguments() {
        let range = RecognizedExpression.list([revenue, cost, .account("Tax")])
        #expect(RecognizedExpression.call("SUM", [range]).rendered() == "SUM(Revenue, Cost, Tax)")
    }

    @Test func aRefusalRendersAsAPlaceholder() {
        #expect(RecognizedExpression.refused.rendered() == "0", "a placeholder standing where a formula would have been — the account carrying it goes to residue, so the zero is never evaluated")
    }

    // MARK: - Reading the tree

    @Test func accountsAreListedInReadingOrder() {
        let expression = RecognizedExpression.binary(
            .add,
            .binary(.multiply, revenue, .account("Margin")),
            .negated(cost))
        #expect(expression.accounts == ["Revenue", "Margin", "Cost"])
    }

    @Test func literalsReadNoAccounts() {
        #expect(RecognizedExpression.number(42).accounts == [])
        #expect(RecognizedExpression.refused.accounts == [])
    }

    @Test func comparisonsAreDistinguishedFromArithmetic() {
        #expect(!RecognizedExpression.Operator.multiply.isComparison)
        #expect(RecognizedExpression.Operator.greaterOrEqual.isComparison)
    }

    // MARK: - Renaming

    /// Renaming structurally, not textually — which is the reason the tree exists
    /// at this point in the pipeline rather than only at the end of it.
    @Test func renamingMatchesWholeAccountsOnly() {
        let expression = RecognizedExpression.binary(
            .add, .account("Debt"), .account("Debt Service"))
        let renamed = expression.renaming("Debt", to: "Opening Debt")

        #expect(renamed.accounts == ["Opening Debt", "Debt Service"])
        #expect(renamed.rendered() == "([Opening Debt] + [Debt Service])", "a string replacement would have rewritten the inside of `Debt Service` too")
    }

    @Test func renamingReachesEveryBranch() {
        let expression = RecognizedExpression.call(
            "SUM",
            [.list([.account("X"), .negated(.account("X"))]),
             .binary(.divide, .account("X"), .number(2))])
        #expect(expression.renaming("X", to: "Y").accounts == ["Y", "Y", "Y"])
    }

    // MARK: - Through recognition

    /// The tree reaches the account, and agrees with the string beside it.
    @Test func aRecognizedAccountCarriesBothFormAndAgrees() throws {
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

        let plan = ExcelRecognizer.recognize(try #require(workbook.sheets.first))
        let ebitda = try #require(plan.model.accounts.first { $0.name == "EBITDA" })

        let expression = try #require(ebitda.expression)
        #expect(expression == .binary(.multiply, .account("Revenue"), .account("Margin")))
        #expect(expression.rendered() == ebitda.formula, "the string is rendered from the tree, so they cannot disagree")
    }

    @Test func anInputAccountHasNoExpression() throws {
        let workbook = Workbook()
        let sheet = workbook.addSheet(name: "Model")
        sheet.write("2024", to: "C1")
        sheet.write("2025", to: "D1")
        sheet.write("2026", to: "E1")
        sheet.write("Revenue", to: "A2")
        for column in ["C", "D", "E"] { sheet.write(1_000.0, to: "\(column)2") }

        let plan = ExcelRecognizer.recognize(try #require(workbook.sheets.first))
        let revenue = try #require(plan.model.accounts.first { $0.name == "Revenue" })

        #expect(revenue.expression == nil, "data has no rule")
        #expect(revenue.formula == nil)
    }
}
