import XCTest
import Foundation
@testable import BusinessMathExcel

/// Compiles and runs the code samples printed in `README.md`.
///
/// README examples are not compiled by anything else, so they drift silently: an API is
/// renamed, the sample keeps reading plausibly, and the first person to hit it is a new
/// user typing it in. These assertions are deliberately shallow — the point is that the
/// sample still builds and produces a workbook, not that the workbook is correct.
final class ReadmeExampleTests: XCTestCase {
    func testReadmeExamplesCompileAndRun() throws {
        let model = ExcelModel()
        let price = model.addInput(label: "Price", value: 100)
        let quantity = model.addInput(label: "Quantity", value: 5)
        let total = model.addOutput(label: "Total", formula: .multiply(.ref(price), .ref(quantity)))

        let workbook = try ModelExporter.export(model, layout: VerticalLayoutStrategy())
        let assignment = VerticalLayoutStrategy().assign(model)
        let totalCell = try XCTUnwrap(assignment.mapping[total]).reference
        let ast = try XCTUnwrap(workbook.sheets[0].formulaAST(at: totalCell))
        // The README claims this exact formula; if layout moves, the README is wrong.
        XCTAssertEqual(FormulaSerializer.serialize(ast), "D4*D5")

        let amort = AmortizationModelBuilder.build(
            principal: 250_000,
            annualRate: 0.065,
            termMonths: 360
        )
        let amortBook = try ModelExporter.export(amort, title: "Amortization")
        XCTAssertGreaterThan(amortBook.sheets.count, 0)
    }
}
