import XCTest
@testable import BusinessMathExcel
import SwiftXLSX

/// Phase 5b — what a number *is*, read from how the sheet presents it.
///
/// The rule, from §18: the format establishes the dimension, the label may
/// sharpen it, and neither invents one. Every format string here is one the
/// Wharton `ANSWER KEY` actually carries.
final class UnitInferenceTests: XCTestCase {

    // MARK: - Dimension from format

    func testACurrencyFormatIsMoney() {
        XCTAssertEqual(UnitInference.dimension(of: "\"$\"#,##0"), .money)
        XCTAssertEqual(
            UnitInference.dimension(of: "_([$$-409]* #,##0.0_);_([$$-409]* \\(#,##0.0\\);_(@_)"),
            .money,
            "Excel's locale-qualified currency, which is what the fixture uses"
        )
    }

    func testAPercentFormatIsAProportion() {
        XCTAssertEqual(UnitInference.dimension(of: "0%"), .ratio)
        XCTAssertEqual(UnitInference.dimension(of: "0.0%"), .ratio)
        XCTAssertEqual(UnitInference.dimension(of: "_(#,##0.0%_);\\(#,##0.0%\\);_(@_)_%"), .ratio)
    }

    /// A multiple is dimensionless, so it is a ratio rather than a unit of its own.
    func testAMultipleFormatIsARatio() {
        XCTAssertEqual(UnitInference.dimension(of: "0.00\"x\""), .ratio)
        XCTAssertEqual(UnitInference.dimension(of: "_(0.0\\x_)_)_';_(\\(0.0\\x\\)_'_';_(@_)_%"), .ratio)
    }

    func testAPeriodFormatIsDuration() {
        XCTAssertEqual(UnitInference.dimension(of: "\"Year\"\\ #"), .duration)
    }

    func testAFormatStatingNothingStatesNothing() {
        XCTAssertNil(UnitInference.dimension(of: "General"))
        XCTAssertNil(
            UnitInference.dimension(of: "_(* #,##0.0_);_(* \\(#,##0.0\\);_(* \"-\"?_);_(@_)"),
            "the accounting format the fixture uses for `Less: Interest` — money by "
                + "any reading, and the format does not say so"
        )
    }

    /// A `%` inside a literal is text, not a unit.
    func testAPercentInsideALiteralIsNotAProportion() {
        XCTAssertNil(UnitInference.dimension(of: "\"100% owned\""))
        XCTAssertNil(UnitInference.dimension(of: "\"$ in millions\""))
    }

    // MARK: - The label sharpens

    func testAProportionNamedAsARateIsARate() {
        XCTAssertEqual(UnitInference.unit(format: "0.0%", label: "Interest Rate"), .rate)
        XCTAssertEqual(UnitInference.unit(format: "0.0%", label: "Revenue growth"), .rate)
        XCTAssertEqual(UnitInference.unit(format: "0.0%", label: "Yield p.a."), .rate)
    }

    /// Where both units fit, the weaker claim wins.
    ///
    /// Calling an interest rate a `ratio` is imprecise but true — a rate *is* a
    /// proportion. Calling a margin a `rate` is false. So a proportion is a ratio
    /// unless the label says otherwise.
    func testAProportionOtherwiseNamedIsARatio() {
        XCTAssertEqual(UnitInference.unit(format: "0.0%", label: "EBITDA margin"), .ratio)
        XCTAssertEqual(UnitInference.unit(format: "0.0%", label: "Debt"), .ratio)
        XCTAssertEqual(UnitInference.unit(format: "0.0%", label: "Tax Rate"), .rate)
    }

    func testTheLabelDoesNotSharpenWhatItCannot() {
        XCTAssertEqual(
            UnitInference.unit(format: "\"$\"#,##0", label: "Interest Rate"), .money,
            "a label saying `rate` does not turn a currency format into a rate"
        )
    }

    /// A label alone is not evidence.
    func testALabelWithNoFormatGivesNoUnit() {
        XCTAssertNil(
            UnitInference.unit(format: "General", label: "Interest Rate"),
            "the label modifies evidence; it is not evidence. A workbook that "
                + "formats nothing has said nothing"
        )
        XCTAssertNil(UnitInference.unit(format: nil, label: "Revenue"))
    }

    // MARK: - Across an account's cells

    func testAnAccountTakesTheUnitItsCellsAgreeOn() {
        let inferred = UnitInference.infer(
            formats: ["0.0%", "0.0%", "0.0%"], label: "EBITDA margin")
        XCTAssertEqual(inferred.unit, .ratio)
        XCTAssertTrue(inferred.conflicted.isEmpty)
    }

    func testUnformattedCellsDoNotOutvoteTheOnesThatSpeak() {
        let inferred = UnitInference.infer(
            formats: ["General", "\"$\"#,##0", "General"], label: "Revenue")
        XCTAssertEqual(
            inferred.unit, .money,
            "silence is not disagreement — one cell states a dimension and none contradicts it"
        )
    }

    func testCellsStatingDifferentDimensionsConflict() {
        let inferred = UnitInference.infer(
            formats: ["\"$\"#,##0", "0.0%"], label: "Debt")
        XCTAssertNil(inferred.unit, "and no unit is chosen from the two")
        XCTAssertEqual(Set(inferred.conflicted), [.money, .ratio])
    }

    func testAnAccountStatingNothingHasNoUnit() {
        let inferred = UnitInference.infer(formats: ["General", "General"], label: "Revenue")
        XCTAssertNil(inferred.unit)
        XCTAssertTrue(inferred.conflicted.isEmpty, "silence is not a conflict")
    }
}
