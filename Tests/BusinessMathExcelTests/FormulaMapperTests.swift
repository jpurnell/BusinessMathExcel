import XCTest
@testable import BusinessMathExcel

final class FormulaMapperTests: XCTestCase {

    // MARK: - Financial Functions

    func testRecognizesPMT() {
        let model = ExcelModel()
        let rate = model.addInput(label: "Rate", value: 0.005)
        model.addFormula(
            label: "Payment",
            formula: .pmt(rate: .ref(rate), nper: .number(360), pv: .number(250_000))
        )

        let result = FormulaMapper.map(model)
        XCTAssertEqual(result.financialMappings.count, 1)
        XCTAssertEqual(result.financialMappings.first?.function, "PMT")
    }

    func testRecognizesNPV() {
        let model = ExcelModel()
        let rate = model.addInput(label: "Rate", value: 0.10)
        model.addOutput(
            label: "NPV",
            formula: .npv(rate: .ref(rate), values: [.number(100), .number(200)])
        )

        let result = FormulaMapper.map(model)
        XCTAssertEqual(result.financialMappings.count, 1)
        XCTAssertEqual(result.financialMappings.first?.function, "NPV")
    }

    func testRecognizesIRR() {
        let model = ExcelModel()
        model.addOutput(
            label: "IRR",
            formula: .irr([.number(-1000), .number(500), .number(600)])
        )

        let result = FormulaMapper.map(model)
        XCTAssertEqual(result.financialMappings.count, 1)
        XCTAssertEqual(result.financialMappings.first?.function, "IRR")
    }

    func testRecognizesIPMTAndPPMT() {
        let model = ExcelModel()
        let rate = model.addInput(label: "Rate", value: 0.005)
        model.addFormula(
            label: "Interest",
            formula: .ipmt(rate: .ref(rate), per: .number(1), nper: .number(360), pv: .number(100_000))
        )
        model.addFormula(
            label: "Principal",
            formula: .ppmt(rate: .ref(rate), per: .number(1), nper: .number(360), pv: .number(100_000))
        )

        let result = FormulaMapper.map(model)
        XCTAssertEqual(result.financialMappings.count, 2)
        let names = result.financialMappings.map(\.function)
        XCTAssertTrue(names.contains("IPMT"))
        XCTAssertTrue(names.contains("PPMT"))
    }

    // MARK: - Statistical Functions

    func testRecognizesAVERAGE() {
        let model = ExcelModel()
        model.addFormula(
            label: "Mean",
            formula: .function("AVERAGE", [.number(1), .number(2), .number(3)])
        )

        let result = FormulaMapper.map(model)
        XCTAssertEqual(result.statisticalMappings.count, 1)
        XCTAssertEqual(result.statisticalMappings.first?.function, "AVERAGE")
    }

    func testRecognizesSUM() {
        let model = ExcelModel()
        model.addFormula(
            label: "Total",
            formula: .sum([.number(10), .number(20)])
        )

        let result = FormulaMapper.map(model)
        XCTAssertEqual(result.statisticalMappings.count, 1)
        XCTAssertEqual(result.statisticalMappings.first?.function, "SUM")
    }

    func testRecognizesSTDEV() {
        let model = ExcelModel()
        model.addFormula(
            label: "StdDev",
            formula: .function("STDEV", [.number(1), .number(2)])
        )

        let result = FormulaMapper.map(model)
        XCTAssertEqual(result.statisticalMappings.count, 1)
        XCTAssertEqual(result.statisticalMappings.first?.function, "STDEV")
    }

    func testRecognizesPERCENTILE() {
        let model = ExcelModel()
        model.addFormula(
            label: "P50",
            formula: .function("PERCENTILE", [.number(1), .number(0.5)])
        )

        let result = FormulaMapper.map(model)
        XCTAssertEqual(result.statisticalMappings.count, 1)
        XCTAssertEqual(result.statisticalMappings.first?.function, "PERCENTILE")
    }

    // MARK: - Unknown Functions

    func testUnknownFunctionReported() {
        let model = ExcelModel()
        model.addFormula(
            label: "Custom",
            formula: .function("MYFUNC", [.number(1)])
        )

        let result = FormulaMapper.map(model)
        XCTAssertEqual(result.unmappedFunctions, ["MYFUNC"])
        XCTAssertTrue(result.financialMappings.isEmpty)
        XCTAssertTrue(result.statisticalMappings.isEmpty)
    }

    // MARK: - Mixed Models

    func testMixedFinancialAndStatistical() {
        let model = ExcelModel()
        let rate = model.addInput(label: "Rate", value: 0.005)
        model.addFormula(
            label: "Payment",
            formula: .pmt(rate: .ref(rate), nper: .number(360), pv: .number(250_000))
        )
        model.addFormula(
            label: "Total",
            formula: .sum([.number(1), .number(2)])
        )

        let result = FormulaMapper.map(model)
        XCTAssertEqual(result.financialMappings.count, 1)
        XCTAssertEqual(result.statisticalMappings.count, 1)
    }

    // MARK: - Nested Functions

    func testNestedFunctionsAllRecognized() {
        let model = ExcelModel()
        model.addOutput(
            label: "Result",
            formula: .add(
                .function("SUM", [.number(1), .number(2)]),
                .function("PMT", [.number(0.005), .number(360), .number(100_000)])
            )
        )

        let result = FormulaMapper.map(model)
        XCTAssertEqual(result.financialMappings.count, 1)
        XCTAssertEqual(result.statisticalMappings.count, 1)
    }

    // MARK: - Empty Model

    func testEmptyModelProducesEmptyResult() {
        let model = ExcelModel()
        let result = FormulaMapper.map(model)
        XCTAssertTrue(result.financialMappings.isEmpty)
        XCTAssertTrue(result.statisticalMappings.isEmpty)
        XCTAssertTrue(result.unmappedFunctions.isEmpty)
    }

    // MARK: - Input-Only Model

    func testInputOnlyModelHasNoMappings() {
        let model = ExcelModel()
        model.addInput(label: "A", value: 1)
        model.addInput(label: "B", value: 2)

        let result = FormulaMapper.map(model)
        XCTAssertTrue(result.financialMappings.isEmpty)
        XCTAssertTrue(result.statisticalMappings.isEmpty)
    }
}
