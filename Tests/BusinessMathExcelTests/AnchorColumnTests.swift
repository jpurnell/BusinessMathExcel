import Foundation
import Testing
@testable import BusinessMathExcel
import SwiftXLSX

/// The column before the timeline.
///
/// A transaction model has a value that belongs to a series but to no period: the
/// equity written at close, the opening balance, the purchase price. Wharton puts
/// it in the column left of its first year, headed `Closing`, and the IRR range
/// starts there — `D61:I61` against an axis of `E27:J27`.
///
/// Binding anchored on the period axis, which Phase 2 chose deliberately, cannot
/// see it: every value in a series is assumed to sit in a period column. So the
/// anchor is recognized separately and kept separate — it is not a period, and
/// treating it as one would put a cash flow in a year it did not happen.
@Suite struct AnchorColumnTests {

    private func build(_ make: (Worksheet) -> Void) -> (SheetGrid, PeriodAxis)? {
        let wb = Workbook()
        let sheet = wb.addSheet(name: "Model")
        make(sheet)
        let grid = SheetGrid.build(from: ModelImporter.importSheet(sheet))
        guard let axis = PeriodAxis.build(from: grid).axis else { return nil }
        return (grid, axis)
    }

    // MARK: - Detection

    @Test func aHeadedColumnOfNumbersBeforeTheTimelineIsAnAnchor() throws {
        let result = try #require(build { sheet in
            sheet.write("Cash Flow", to: "A2")
            sheet.write("Closing", to: "B1")
            sheet.write("2024", to: "C1")
            sheet.write("2025", to: "D1")
            sheet.write(-80.0, to: "B2")
            sheet.write(10.0, to: "C2")
            sheet.write(20.0, to: "D2")
        })

        let anchor = try #require(result.1.anchor)
        #expect(anchor.label == "Closing")
        #expect(anchor.source.reference == "B1")
    }

    @Test func theAnchorIsNotCountedAsAPeriod() throws {
        let result = try #require(build { sheet in
            sheet.write("Cash Flow", to: "A2")
            sheet.write("Closing", to: "B1")
            sheet.write("2024", to: "C1")
            sheet.write("2025", to: "D1")
            sheet.write(-80.0, to: "B2")
            sheet.write(10.0, to: "C2")
            sheet.write(20.0, to: "D2")
        })

        #expect(result.1.count == 2, "two years, and the anchor is not one of them")
        #expect(result.1.sources.map(\.reference) == ["C1", "D1"])
    }

    // MARK: - What is not an anchor

    @Test func aLabelColumnIsNotAnAnchor() throws {
        // The discriminator is what sits *below* the heading. A label column holds
        // text; an anchor column holds figures. Without that, every sheet whose row
        // labels happen to sit against the timeline would grow a phantom period.
        let result = try #require(build { sheet in
            sheet.write("Revenue", to: "B2")
            sheet.write("Cost", to: "B3")
            sheet.write("Detail", to: "B1")
            sheet.write("2024", to: "C1")
            sheet.write("2025", to: "D1")
            sheet.write(10.0, to: "C2")
            sheet.write(20.0, to: "D2")
            sheet.write(4.0, to: "C3")
            sheet.write(5.0, to: "D3")
        })

        #expect(result.1.anchor == nil, "a column of labels is not a column of values")
    }

    @Test func anUnheadedColumnIsNotAnAnchor() throws {
        let result = try #require(build { sheet in
            sheet.write("Cash Flow", to: "A2")
            sheet.write("2024", to: "C1")
            sheet.write("2025", to: "D1")
            sheet.write(-80.0, to: "B2")
            sheet.write(10.0, to: "C2")
            sheet.write(20.0, to: "D2")
        })

        #expect(result.1.anchor == nil, "without a heading there is nothing to say it is one")
    }

    @Test func aYearBeforeTheTimelineIsAPeriodNotAnAnchor() throws {
        // If it parses as a period it would have joined the axis already.
        let result = try #require(build { sheet in
            sheet.write("Cash Flow", to: "A2")
            sheet.write("2023", to: "B1")
            sheet.write("2024", to: "C1")
            sheet.write("2025", to: "D1")
            for column in ["B", "C", "D"] { sheet.write(10.0, to: "\(column)2") }
        })

        #expect(result.1.anchor == nil)
        #expect(result.1.count == 3, "it is simply the first year")
    }

    // MARK: - Binding

    @Test func aSeriesCarriesItsAnchorValueSeparately() throws {
        let result = try #require(build { sheet in
            sheet.write("Cash Flow", to: "A2")
            sheet.write("Closing", to: "B1")
            sheet.write("2024", to: "C1")
            sheet.write("2025", to: "D1")
            sheet.write(-80.0, to: "B2")
            sheet.write(10.0, to: "C2")
            sheet.write(20.0, to: "D2")
        })

        let (series, _) = LabeledSeries.bind(in: result.0, axis: result.1)
        let flow = try #require(series.first { $0.name == "Cash Flow" })

        #expect(flow.anchorCell?.reference == "B2")
        #expect(flow.cells.map { $0?.reference } == ["C2", "D2"], "the period cells stay aligned to the axis, as Phase 2 promised")
    }

    @Test func aSeriesWithNothingInTheAnchorColumnHasNoAnchorCell() throws {
        let result = try #require(build { sheet in
            sheet.write("Cash Flow", to: "A2")
            sheet.write("Other", to: "A3")
            sheet.write("Closing", to: "B1")
            sheet.write("2024", to: "C1")
            sheet.write("2025", to: "D1")
            sheet.write(-80.0, to: "B2")
            sheet.write(10.0, to: "C2")
            sheet.write(20.0, to: "D2")
            sheet.write(1.0, to: "C3")
            sheet.write(2.0, to: "D3")
        })

        let (series, _) = LabeledSeries.bind(in: result.0, axis: result.1)
        let other = try #require(series.first { $0.name == "Other" })
        #expect(other.anchorCell == nil, "not every row has an at-close value")
    }
}
