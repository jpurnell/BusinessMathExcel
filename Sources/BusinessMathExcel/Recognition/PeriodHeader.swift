import Foundation
import SwiftXLSX

/// Whether a cell's contents read as a time-period heading.
///
/// Detection needs this before ``PeriodAxis`` can convert headings into periods,
/// so the recognizer's notion of "looks like a period" lives here, in one place,
/// where the rule can be read and argued with.
///
/// ## What counts
///
/// A calendar year between 1900 and 2200, written any of the ways a financial
/// model writes one:
///
/// | Form | Example |
/// |---|---|
/// | Bare year | `2024`, or the *number* 2024 |
/// | Fiscal prefix | `FY2024`, `FY 2024`, `FY24` |
/// | Estimate/actual suffix | `2024E`, `2024A`, `2024P`, `2024F` |
///
/// ## What deliberately does not count
///
/// An ordinary number. `100` is not a year, and a row of quantities must not
/// read as a time axis. Two-digit forms are only accepted behind `FY`, because
/// a bare `24` is far more often a quantity than a year.
enum PeriodHeader {

    /// The calendar year a heading names, or `nil` if it does not name one.
    ///
    /// - Parameter text: The cell's text, or its number formatted plainly.
    /// - Returns: A year in 1900...2200.
    static func year(of text: String) -> Int? {
        var token = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !token.isEmpty else { return nil }

        var sawFiscalPrefix = false
        if token.hasPrefix("FY") {
            sawFiscalPrefix = true
            token = String(token.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        }

        // A single trailing estimate/actual/projected/forecast marker.
        if let last = token.last, "EAPF".contains(last), token.count > 1 {
            token = String(token.dropLast())
        }

        guard token.allSatisfy(\.isNumber) else { return nil }

        if token.count == 4, let year = Int(token), (1900...2200).contains(year) {
            return year
        }
        // `FY24` is a year; a bare `24` is much more often a quantity.
        if sawFiscalPrefix, token.count == 2, let short = Int(token) {
            return short >= 70 ? 1900 + short : 2000 + short
        }
        return nil
    }

    /// The calendar year a cell names, from its own contents or from what the
    /// file recorded Excel computing for it.
    ///
    /// The cached fallback matters more than it looks: a header row is very often
    /// `2023` followed by `=E27+1` across, so most of the years in a real model
    /// are computed rather than typed. Refusing to read them would find an axis on
    /// almost no real workbook.
    ///
    /// Using a cached value as *evidence about layout* is not the substitution this
    /// package prohibits. What is banned is putting a cached result into a model in
    /// place of a formula that could not be translated — asserting a value we did
    /// not derive. Deciding that a cell heads a column is a different claim, and a
    /// wrong one is visible immediately as a mis-detected axis.
    ///
    /// - Parameters:
    ///   - kind: The node the cell became.
    ///   - cached: What the file recorded Excel computing for it, if anything.
    /// - Returns: A year in 1900...2200.
    static func year(of kind: NodeKind, cached: CellValue? = nil) -> Int? {
        switch kind {
        case .textInput(let text), .label(let text):
            return year(of: text)
        case .input(let value):
            // A year stored as a number, e.g. a header cell typed as 2024.
            return year(ofNumber: value)
        case .formula, .output:
            switch cached {
            case .number(let value): return year(ofNumber: value)
            case .text(let text): return year(of: text)
            default: return nil
            }
        }
    }

    private static func year(ofNumber value: Double) -> Int? {
        guard value == value.rounded(), value >= 1900, value <= 2200 else { return nil }
        return Int(value)
    }
}
