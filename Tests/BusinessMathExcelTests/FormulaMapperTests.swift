import Foundation
import Testing
@testable import BusinessMathExcel

@Suite struct FormulaMapperTests {

    // MARK: - Financial Functions

    @Test func recognizesPMT() {
        let model = ExcelModel()
        let rate = model.addInput(label: "Rate", value: 0.005)
        model.addFormula(
            label: "Payment",
            formula: .pmt(rate: .ref(rate), nper: .number(360), pv: .number(250_000))
        )

        let result = FormulaMapper.map(model)
        #expect(result.financialMappings.count == 1)
        #expect(result.financialMappings.first?.function == "PMT")
    }

    @Test func recognizesNPV() {
        let model = ExcelModel()
        let rate = model.addInput(label: "Rate", value: 0.10)
        model.addOutput(
            label: "NPV",
            formula: .npv(rate: .ref(rate), values: [.number(100), .number(200)])
        )

        let result = FormulaMapper.map(model)
        #expect(result.financialMappings.count == 1)
        #expect(result.financialMappings.first?.function == "NPV")
    }

    @Test func recognizesIRR() {
        let model = ExcelModel()
        model.addOutput(
            label: "IRR",
            formula: .irr([.number(-1000), .number(500), .number(600)])
        )

        let result = FormulaMapper.map(model)
        #expect(result.financialMappings.count == 1)
        #expect(result.financialMappings.first?.function == "IRR")
    }

    @Test func recognizesIPMTAndPPMT() {
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
        #expect(result.financialMappings.count == 2)
        let names = result.financialMappings.map(\.function)
        #expect(names.contains("IPMT"))
        #expect(names.contains("PPMT"))
    }

    // MARK: - Statistical Functions

    @Test func recognizesAVERAGE() {
        let model = ExcelModel()
        model.addFormula(
            label: "Mean",
            formula: .function("AVERAGE", [.number(1), .number(2), .number(3)])
        )

        let result = FormulaMapper.map(model)
        #expect(result.statisticalMappings.count == 1)
        #expect(result.statisticalMappings.first?.function == "AVERAGE")
    }

    @Test func recognizesSUM() {
        let model = ExcelModel()
        model.addFormula(
            label: "Total",
            formula: .sum([.number(10), .number(20)])
        )

        let result = FormulaMapper.map(model)
        #expect(result.statisticalMappings.count == 1)
        #expect(result.statisticalMappings.first?.function == "SUM")
    }

    @Test func recognizesSTDEV() {
        let model = ExcelModel()
        model.addFormula(
            label: "StdDev",
            formula: .function("STDEV", [.number(1), .number(2)])
        )

        let result = FormulaMapper.map(model)
        #expect(result.statisticalMappings.count == 1)
        #expect(result.statisticalMappings.first?.function == "STDEV")
    }

    @Test func recognizesPERCENTILE() {
        let model = ExcelModel()
        model.addFormula(
            label: "P50",
            formula: .function("PERCENTILE", [.number(1), .number(0.5)])
        )

        let result = FormulaMapper.map(model)
        #expect(result.statisticalMappings.count == 1)
        #expect(result.statisticalMappings.first?.function == "PERCENTILE")
    }

    // MARK: - Unknown Functions

    @Test func unknownFunctionReported() {
        let model = ExcelModel()
        model.addFormula(
            label: "Custom",
            formula: .function("MYFUNC", [.number(1)])
        )

        let result = FormulaMapper.map(model)
        #expect(result.unmappedFunctions == ["MYFUNC"])
        #expect(result.financialMappings.isEmpty)
        #expect(result.statisticalMappings.isEmpty)
    }

    // MARK: - Mixed Models

    @Test func mixedFinancialAndStatistical() {
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
        #expect(result.financialMappings.count == 1)
        #expect(result.statisticalMappings.count == 1)
    }

    // MARK: - Nested Functions

    @Test func nestedFunctionsAllRecognized() {
        let model = ExcelModel()
        model.addOutput(
            label: "Result",
            formula: .add(
                .function("SUM", [.number(1), .number(2)]),
                .function("PMT", [.number(0.005), .number(360), .number(100_000)])
            )
        )

        let result = FormulaMapper.map(model)
        #expect(result.financialMappings.count == 1)
        #expect(result.statisticalMappings.count == 1)
    }

    // MARK: - Empty Model

    @Test func emptyModelProducesEmptyResult() {
        let model = ExcelModel()
        let result = FormulaMapper.map(model)
        #expect(result.financialMappings.isEmpty)
        #expect(result.statisticalMappings.isEmpty)
        #expect(result.unmappedFunctions.isEmpty)
    }

    // MARK: - Input-Only Model

    @Test func inputOnlyModelHasNoMappings() {
        let model = ExcelModel()
        model.addInput(label: "A", value: 1)
        model.addInput(label: "B", value: 2)

        let result = FormulaMapper.map(model)
        #expect(result.financialMappings.isEmpty)
        #expect(result.statisticalMappings.isEmpty)
    }
}
