import XCTest
import SwiftExcelCore
import SwiftXLSX
@testable import BusinessMathExcel

/// Reading a workbook's own account of what is uncertain.
///
/// The point of the bridge is that this needs no add-in, no seed and no simulation
/// engine — an archived Risk Solver model has none of those, and its formulas still
/// say which cells draw and which are collected.
final class SimulationInputsTests: XCTestCase {

    /// A sheet with two draws, an output marker, and an ordinary formula.
    private func modelWorkbook() -> Workbook {
        let workbook = Workbook()
        let sheet = workbook.addSheet(name: "Model")
        sheet.writeFormula("_xll.PsiTriangular(80,100,130)", to: "B2")
        sheet.writeFormula("_xll.PsiNormal(0.08,0.02)", to: "B3")
        sheet.writeFormula("B2*B3", to: "B4")
        sheet.writeFormula("SUM(B2:B4)+_xll.PsiOutput()", to: "B5")
        return workbook
    }

    /// Both draws are found, each numbered, and neither the plain formula nor the
    /// output marker is mistaken for one.
    func testTheDrawsAreFoundAndIndexed() {
        let found = SimulationInputs.survey(modelWorkbook(), sheet: "Model")
        XCTAssertEqual(found.inputCount, 2)
        XCTAssertEqual(found.uncertain.map(\.address.reference).sorted(), ["B2", "B3"])
        XCTAssertEqual(Set(found.uncertain.map(\.inputIndex)), [0, 1],
                       "each uncertain cell gets its own index")
    }

    /// `PsiOutput()` marks the cell it is attached to, and that cell is an output
    /// rather than a draw — the marker contributes nothing to the arithmetic.
    func testTheOutputMarkerIsFoundAndIsNotADraw() {
        let found = SimulationInputs.survey(modelWorkbook(), sheet: "Model")
        XCTAssertEqual(found.outputs.map(\.reference), ["B5"])
        XCTAssertFalse(found.uncertain.contains { $0.address.reference == "B5" })
    }

    /// A sheet with no simulation in it says so, which is what lets a recognizer skip
    /// the sheets that are not models — most of them, in a real workbook.
    func testASheetWithNoSimulationIsReportedAsSuch() {
        let workbook = Workbook()
        let sheet = workbook.addSheet(name: "Assumptions")
        sheet.writeFormula("A1*2", to: "B1")
        sheet.write(42, to: "A1")
        XCTAssertFalse(SimulationInputs.isSimulated(workbook, sheet: "Assumptions"))
        XCTAssertTrue(SimulationInputs.isSimulated(modelWorkbook(), sheet: "Model"))
    }

    /// Nothing is evaluated, so a distribution with no random source anywhere in
    /// sight is still recognised. That is the whole reason recognition is separate
    /// from evaluation.
    func testRecognitionNeedsNoRandomSource() {
        let found = SimulationInputs.survey(modelWorkbook(), sheet: "Model")
        XCTAssertEqual(found.uncertain.map(\.call.function).sorted(),
                       ["PSINORMAL", "PSITRIANGULAR"])
    }
}
