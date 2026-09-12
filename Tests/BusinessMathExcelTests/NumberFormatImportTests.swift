import XCTest
@testable import BusinessMathExcel
import SwiftXLSX

/// Phase 5b Task 1 — a cell's number format reaching the stages that interpret.
///
/// A format is frequently the only statement a workbook makes about what a number
/// *is*. It is carried, not interpreted, at this layer: `Import/` never decides
/// what anything means, and `Recognition/` cannot decide without the evidence.
final class NumberFormatImportTests: XCTestCase {

    private func sheet(_ build: (Worksheet) -> Void) -> Worksheet {
        let workbook = Workbook()
        let sheet = workbook.addSheet(name: "Model")
        build(sheet)
        return sheet
    }

    func testTheImporterCarriesEachCellsNumberFormat() throws {
        let sheet = sheet {
            $0.write(1_000_000.0, to: "B2", style: .general.with(numberFormat: .currency))
            $0.write(0.4, to: "B3", style: .general.with(numberFormat: .percent))
        }

        let result = ModelImporter.importSheet(sheet)
        XCTAssertEqual(result.numberFormats[CellRef("B2")], "$#,##0.00")
        XCTAssertEqual(result.numberFormats[CellRef("B3")], "0.00%")
    }

    func testAGeneralFormatIsCarriedAsWritten() throws {
        let sheet = sheet { $0.write(5.0, to: "B2") }

        XCTAssertEqual(
            ModelImporter.importSheet(sheet).numberFormats[CellRef("B2")], "General",
            "carried rather than dropped — 'General' is what the file says, and "
                + "deciding it means nothing is the next stage's job"
        )
    }

    func testTheGridCarriesFormatsThrough() throws {
        let sheet = sheet {
            $0.write("2024", to: "C1")
            $0.write("2025", to: "D1")
            $0.write("2026", to: "E1")
            $0.write("Revenue", to: "A2")
            for column in ["C", "D", "E"] {
                $0.write(100.0, to: "\(column)2", style: .general.with(numberFormat: .currency))
            }
        }

        let grid = SheetGrid.build(from: ModelImporter.importSheet(sheet))
        XCTAssertEqual(grid.numberFormats[CellRef("D2")], "$#,##0.00")
    }

    func testASheetWithNoStylesCarriesNoSurprises() throws {
        let sheet = sheet { $0.write("Revenue", to: "A2") }
        let result = ModelImporter.importSheet(sheet)

        XCTAssertEqual(result.numberFormats[CellRef("A2")], "General")
        XCTAssertNil(result.numberFormats[CellRef("Z99")], "nothing is there")
        XCTAssertTrue(result.warnings.isEmpty, "Got: \(result.warnings)")
    }
}
