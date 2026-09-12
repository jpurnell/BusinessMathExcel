import XCTest
@testable import BusinessMathExcel
import SwiftXLSX

/// Stage 1 — cell topology and period-axis detection.
final class SheetGridTests: XCTestCase {

    private func grid(
        _ build: (Worksheet) -> Void,
        options: RecognizerOptions = RecognizerOptions()
    ) -> SheetGrid {
        let wb = Workbook()
        let sheet = wb.addSheet(name: "Model")
        build(sheet)
        return SheetGrid.build(from: ModelImporter.importSheet(sheet), options: options)
    }

    // MARK: - Orientation

    func testYearsAcrossTheTopReadAsPeriodsAcrossColumns() {
        let grid = grid { sheet in
            sheet.write("Revenue", to: "A2")
            for (offset, year) in [2024, 2025, 2026].enumerated() {
                sheet.write("\(year)", to: "\(["B", "C", "D"][offset])1")
                sheet.write(Double(100 + offset), to: "\(["B", "C", "D"][offset])2")
            }
        }

        XCTAssertEqual(grid.orientation, .periodsAcrossColumns)
        XCTAssertEqual(grid.axisCells.map(\.reference), ["B1", "C1", "D1"])
        XCTAssertTrue(grid.diagnostics.isEmpty, "Got: \(grid.diagnostics)")
    }

    func testYearsDownTheSideReadAsPeriodsDownRows() {
        let grid = grid { sheet in
            sheet.write("Revenue", to: "B1")
            for (offset, year) in [2024, 2025, 2026].enumerated() {
                sheet.write("\(year)", to: "A\(offset + 2)")
                sheet.write(Double(100 + offset), to: "B\(offset + 2)")
            }
        }

        XCTAssertEqual(grid.orientation, .periodsDownRows)
        XCTAssertEqual(grid.axisCells.map(\.reference), ["A2", "A3", "A4"])
    }

    func testASheetReadableBothWaysIsAmbiguousAndPicksNeither() {
        // Years across row 1 and years down column A, same length. Choosing either
        // would be a coin toss presented as an answer.
        let grid = grid { sheet in
            for (offset, year) in [2024, 2025, 2026].enumerated() {
                sheet.write("\(year)", to: "\(["B", "C", "D"][offset])1")
                sheet.write("\(year)", to: "A\(offset + 2)")
            }
        }

        XCTAssertNil(grid.orientation, "Not guessing is the feature")
        XCTAssertEqual(grid.diagnostics.map(\.code), [.ambiguousOrientation])
    }

    func testASheetWithNoPeriodHeadersReportsNoAxis() {
        let grid = grid { sheet in
            sheet.write("Revenue", to: "A1")
            sheet.write(100.0, to: "B1")
        }

        XCTAssertNil(grid.orientation)
        XCTAssertEqual(grid.diagnostics.map(\.code), [.noPeriodAxis])
    }

    func testASingleYearIsNotAnAxis() {
        // One header is a label. An axis needs at least two periods to establish
        // a direction.
        let grid = grid { sheet in
            sheet.write("2024", to: "B1")
            sheet.write(100.0, to: "B2")
        }

        XCTAssertNil(grid.orientation)
        XCTAssertEqual(grid.diagnostics.map(\.code), [.noPeriodAxis])
    }

    func testYearsThatDoNotAdvanceAreNotAnAxis() {
        let grid = grid { sheet in
            for column in ["B", "C", "D"] {
                sheet.write("2024", to: "\(column)1")
            }
        }

        XCTAssertNil(grid.orientation)
        XCTAssertEqual(grid.diagnostics.map(\.code), [.noPeriodAxis])
    }

    func testHeadersMustBeContiguousAlongTheLine() {
        // B1 and D1 are years with a gap at C1: two separate runs of one, not a
        // run of two.
        let grid = grid { sheet in
            sheet.write("2024", to: "B1")
            sheet.write("Notes", to: "C1")
            sheet.write("2025", to: "D1")
        }

        XCTAssertNil(grid.orientation)
    }

    // MARK: - Header Forms

    func testRecognizesTheHeaderFormsModelsActuallyUse() {
        for headers in [["2024", "2025"], ["FY2024", "FY2025"], ["FY24", "FY25"],
                        ["2024E", "2025E"], ["2024A", "2025P"]] {
            let grid = grid { sheet in
                sheet.write(headers[0], to: "B1")
                sheet.write(headers[1], to: "C1")
            }
            XCTAssertEqual(
                grid.orientation, .periodsAcrossColumns, "\(headers) should read as an axis")
        }
    }

    func testRecognizesAYearStoredAsANumber() {
        let grid = grid { sheet in
            sheet.write(2024.0, to: "B1")
            sheet.write(2025.0, to: "C1")
        }
        XCTAssertEqual(grid.orientation, .periodsAcrossColumns)
    }

    func testDoesNotMistakeOrdinaryNumbersForYears() {
        let grid = grid { sheet in
            sheet.write(100.0, to: "B1")
            sheet.write(200.0, to: "C1")
        }
        XCTAssertNil(grid.orientation)
    }

    // MARK: - Topology

    func testAnEmptySheetHasNoBoundsAndNoAxis() {
        let grid = grid { _ in }

        XCTAssertEqual(grid.populatedCells, 0)
        XCTAssertNil(grid.bounds)
        XCTAssertNil(grid.orientation)
        XCTAssertEqual(grid.diagnostics.map(\.code), [.noPeriodAxis])
    }

    func testBoundsSpanThePopulatedCells() {
        let grid = grid { sheet in
            sheet.write(1.0, to: "B2")
            sheet.write(2.0, to: "D5")
        }

        XCTAssertEqual(grid.bounds?.reference, "B2:D5")
        XCTAssertEqual(grid.populatedCells, 2)
    }

    // MARK: - Options

    func testForcedOrientationOverridesDetection() {
        var options = RecognizerOptions()
        options.orientation = .periodsDownRows

        let grid = grid({ sheet in
            sheet.write("2024", to: "B1")
            sheet.write("2025", to: "C1")
        }, options: options)

        XCTAssertEqual(grid.orientation, .periodsDownRows, "A caller's declaration wins")
    }

    func testExceedingTheScanLimitIsReported() {
        var options = RecognizerOptions()
        options.maximumCells = 2

        let grid = grid({ sheet in
            for row in 1...5 { sheet.write(Double(row), to: "A\(row)") }
        }, options: options)

        XCTAssertTrue(grid.diagnostics.contains { $0.code == .scanLimitReached })
    }
}
