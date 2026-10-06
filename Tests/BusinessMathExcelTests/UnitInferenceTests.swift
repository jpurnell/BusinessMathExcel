import Foundation
import Testing
@testable import BusinessMathExcel
import SwiftXLSX

/// Phase 5b — what a number *is*, read from how the sheet presents it.
///
/// The rule, from §18: the format establishes the dimension, the label may
/// sharpen it, and neither invents one. Every format string here is one the
/// Wharton `ANSWER KEY` actually carries.
@Suite struct UnitInferenceTests {

    // MARK: - Dimension from format

    @Test func aCurrencyFormatIsMoney() {
        #expect(UnitInference.dimension(of: "\"$\"#,##0") == .money)
        #expect(UnitInference.dimension(of: "_([$$-409]* #,##0.0_);_([$$-409]* \\(#,##0.0\\);_(@_)") == .money, "Excel's locale-qualified currency, which is what the fixture uses")
    }

    @Test func aPercentFormatIsAProportion() {
        #expect(UnitInference.dimension(of: "0%") == .ratio)
        #expect(UnitInference.dimension(of: "0.0%") == .ratio)
        #expect(UnitInference.dimension(of: "_(#,##0.0%_);\\(#,##0.0%\\);_(@_)_%") == .ratio)
    }

    /// A multiple is dimensionless, so it is a ratio rather than a unit of its own.
    @Test func aMultipleFormatIsARatio() {
        #expect(UnitInference.dimension(of: "0.00\"x\"") == .ratio)
        #expect(UnitInference.dimension(of: "_(0.0\\x_)_)_';_(\\(0.0\\x\\)_'_';_(@_)_%") == .ratio)
    }

    @Test func aPeriodFormatIsDuration() {
        #expect(UnitInference.dimension(of: "\"Year\"\\ #") == .duration)
    }

    @Test func aFormatStatingNothingStatesNothing() {
        #expect(UnitInference.dimension(of: "General") == nil)
        #expect(UnitInference.dimension(of: "_(* #,##0.0_);_(* \\(#,##0.0\\);_(* \"-\"?_);_(@_)") == nil, "the accounting format the fixture uses for `Less: Interest` — money by any reading, and the format does not say so")
    }

    /// A backslash inside a literal must not eat the quote that closes it.
    ///
    /// `\` and `_` are both skip markers outside a literal and mean nothing inside
    /// one. Written as a single `case "\\", "_" where !inLiteral` they did not
    /// behave alike — the guard binds to the last pattern only — so a backslash in
    /// a literal consumed the following character, which can be the closing quote.
    /// The literal then ran on and swallowed the rest of the format.
    @Test func aBackslashInsideALiteralDoesNotEndItEarly() {
        // A literal ending in a backslash, then a real percent outside it. Excel
        // has no `\"` escape — a literal simply ends at the next quote — so the
        // quote here closes it and `0%` is a proportion.
        #expect(UnitInference.dimension(of: #""a\"0%"#) == .ratio, "the backslash must not consume the quote that closes the literal")
        #expect(UnitInference.dimension(of: #""100\% owned""#) == nil, "and a percent that is only ever inside a literal is still a caption")
    }

    /// A `%` inside a literal is text, not a unit.
    @Test func aPercentInsideALiteralIsNotAProportion() {
        #expect(UnitInference.dimension(of: "\"100% owned\"") == nil)
        #expect(UnitInference.dimension(of: "\"$ in millions\"") == nil)
    }

    // MARK: - The label sharpens

    @Test func aProportionNamedAsARateIsARate() {
        #expect(UnitInference.unit(format: "0.0%", label: "Interest Rate") == .rate)
        #expect(UnitInference.unit(format: "0.0%", label: "Revenue growth") == .rate)
        #expect(UnitInference.unit(format: "0.0%", label: "Yield p.a.") == .rate)
    }

    /// Where both units fit, the weaker claim wins.
    ///
    /// Calling an interest rate a `ratio` is imprecise but true — a rate *is* a
    /// proportion. Calling a margin a `rate` is false. So a proportion is a ratio
    /// unless the label says otherwise.
    @Test func aProportionOtherwiseNamedIsARatio() {
        #expect(UnitInference.unit(format: "0.0%", label: "EBITDA margin") == .ratio)
        #expect(UnitInference.unit(format: "0.0%", label: "Debt") == .ratio)
        #expect(UnitInference.unit(format: "0.0%", label: "Tax Rate") == .rate)
    }

    @Test func theLabelDoesNotSharpenWhatItCannot() {
        #expect(UnitInference.unit(format: "\"$\"#,##0", label: "Interest Rate") == .money, "a label saying `rate` does not turn a currency format into a rate")
    }

    /// A label alone is not evidence.
    @Test func aLabelWithNoFormatGivesNoUnit() {
        #expect(UnitInference.unit(format: "General", label: "Interest Rate") == nil, "the label modifies evidence; it is not evidence. A workbook that formats nothing has said nothing")
        #expect(UnitInference.unit(format: nil, label: "Revenue") == nil)
    }

    // MARK: - Across an account's cells

    @Test func anAccountTakesTheUnitItsCellsAgreeOn() {
        let inferred = UnitInference.infer(
            formats: ["0.0%", "0.0%", "0.0%"], label: "EBITDA margin")
        #expect(inferred.unit == .ratio)
        #expect(inferred.conflicted.isEmpty)
    }

    @Test func unformattedCellsDoNotOutvoteTheOnesThatSpeak() {
        let inferred = UnitInference.infer(
            formats: ["General", "\"$\"#,##0", "General"], label: "Revenue")
        #expect(inferred.unit == .money, "silence is not disagreement — one cell states a dimension and none contradicts it")
    }

    @Test func cellsStatingDifferentDimensionsConflict() {
        let inferred = UnitInference.infer(
            formats: ["\"$\"#,##0", "0.0%"], label: "Debt")
        #expect(inferred.unit == nil, "and no unit is chosen from the two")
        #expect(Set(inferred.conflicted) == [.money, .ratio])
    }

    @Test func anAccountStatingNothingHasNoUnit() {
        let inferred = UnitInference.infer(formats: ["General", "General"], label: "Revenue")
        #expect(inferred.unit == nil)
        #expect(inferred.conflicted.isEmpty, "silence is not a conflict")
    }

    // MARK: - Through the recognizer

    private func recognized(_ build: (Worksheet) -> Void) -> RecognitionResult {
        let workbook = Workbook()
        let sheet = workbook.addSheet(name: "Model")
        sheet.write("2024", to: "C1")
        sheet.write("2025", to: "D1")
        sheet.write("2026", to: "E1")
        build(sheet)
        guard let first = workbook.sheets.first else {
            preconditionFailure("the fixture always has a sheet")
        }
        return ExcelRecognizer.recognize(first)
    }

    @Test func anAccountCarriesTheUnitItsCellsState() throws {
        let plan = recognized { sheet in
            sheet.write("Revenue", to: "A2")
            for column in ["C", "D", "E"] {
                sheet.write(
                    100.0, to: "\(column)2", style: .general.with(numberFormat: .currency))
            }
        }

        let revenue = try #require(plan.model.accounts.first { $0.name == "Revenue" })
        #expect(revenue.unit == .money)
    }

    @Test func anAccountStatingNothingIsReportedButNotWarnedAbout() throws {
        let plan = recognized { sheet in
            sheet.write("Revenue", to: "A2")
            for column in ["C", "D", "E"] { sheet.write(100.0, to: "\(column)2") }
        }

        let revenue = try #require(plan.model.accounts.first { $0.name == "Revenue" })
        #expect(revenue.unit == nil)

        let reported = try #require(plan.diagnostics.first { $0.code == .unitInferenceFailed }, "Got: \(plan.diagnostics.map(\.code.rawValue))")
        #expect(reported.severity == .info, "a workbook that formats nothing is not defective, and a hundred warnings would bury the findings that matter")
    }

    @Test func anAccountWhoseCellsDisagreeReportsTheConflict() throws {
        let plan = recognized { sheet in
            sheet.write("Debt", to: "A2")
            sheet.write(100.0, to: "C2", style: .general.with(numberFormat: .currency))
            sheet.write(0.6, to: "D2", style: .general.with(numberFormat: .percent))
            sheet.write(100.0, to: "E2", style: .general.with(numberFormat: .currency))
        }

        let debt = try #require(plan.model.accounts.first { $0.name == "Debt" })
        #expect(debt.unit == nil, "no unit is chosen from two that disagree")
        #expect(plan.diagnostics.filter { $0.code == .unitConflict }.count == 1, "Got: \(plan.diagnostics.map(\.code.rawValue))")
    }

    @Test func anAssumptionCarriesItsUnitToo() throws {
        // Its own sheet: an assumption must sit *above* the timeline, so the
        // shared fixture's year row on row 1 leaves nowhere to put one.
        let workbook = Workbook()
        let sheet = workbook.addSheet(name: "Model")
        sheet.write("Interest Rate", to: "A2")
        sheet.write(0.1, to: "B2", style: .general.with(numberFormat: .percent))
        sheet.write("2024", to: "C5")
        sheet.write("2025", to: "D5")
        sheet.write("2026", to: "E5")
        sheet.write("Charge", to: "A6")
        for column in ["C", "D", "E"] { sheet.write(10.0, to: "\(column)6") }
        let plan = ExcelRecognizer.recognize(try #require(workbook.sheets.first))

        let rate = try #require(plan.model.accounts.first { $0.name == "Interest Rate" }, "Got: \(plan.model.accounts.map(\.name))")
        #expect(rate.unit == .rate, "a proportion the label calls a rate")
    }
}
