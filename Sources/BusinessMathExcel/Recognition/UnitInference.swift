import Foundation

/// Stage 5 — what a number *is*, read from how the sheet presents it.
///
/// ## Where the evidence comes from
///
/// A workbook rarely states a unit. What it states is a **number format**, and
/// that is frequently the only thing it says about meaning: `0.4` formatted `0%`
/// is a proportion, the same `0.4` formatted `"$"#,##0` is money, and the label
/// beside either may say neither.
///
/// The rule is one sentence. **The format establishes the dimension, the label may
/// sharpen it, and neither invents one.**
///
/// ## Why the label cannot lead
///
/// A label is a name, not a measurement. `Interest Rate` beside a currency format
/// is a currency amount that someone named badly, and taking the label's word for
/// it would overrule the only hard evidence on the page. So the label is admitted
/// as a *modifier* of a dimension the format already established, and never as a
/// substitute for one.
///
/// ## Where two units fit, the weaker claim wins
///
/// A format cannot separate ``UnitKind/rate`` from ``UnitKind/ratio``: `0.0%` is
/// what `Interest Rate`, `EBITDA margin`, `Revenue growth` and a debt percentage
/// all carry on the Wharton `ANSWER KEY`. Only the label distinguishes them, and
/// it does so unreliably.
///
/// So a proportion is a ``UnitKind/ratio`` unless the label says it is per period.
/// The asymmetry is the whole of the judgment here: calling an interest rate a
/// `ratio` is **imprecise but true**, since a rate is a proportion; calling a
/// margin a `rate` is **false**. Where the evidence supports both, this takes the
/// claim that cannot be wrong.
///
/// ## Silence is a result
///
/// 148 of the `ANSWER KEY`'s 279 populated cells are formatted `General`. An
/// account whose cells state nothing gets no unit, and that is reported at `info`
/// rather than `warning`: a workbook that formats nothing is not defective, and a
/// hundred warnings would bury the findings that matter.
public enum UnitInference {

    /// What inferring a unit across an account's cells found.
    public struct Inferred: Sendable, Equatable {

        /// The unit, or `nil` when the cells stated none or disagreed.
        public let unit: UnitKind?

        /// The dimensions found, when the cells stated more than one.
        ///
        /// Empty when they agreed or said nothing. A row holding both money and a
        /// proportion is either a modelling error or a row bound to the wrong
        /// cells, and both are worth seeing.
        public let conflicted: [UnitKind]
    }

    /// The dimension a number format states, if any.
    ///
    /// Two details of Excel's format grammar decide this, and both appear in the
    /// Wharton fixture:
    ///
    /// - A currency symbol is usually written **inside** a literal — `"$"#,##0` —
    ///   so ignoring literals loses the commonest way money is stated. But a
    ///   literal is also where captions live, and `"$ in millions"` is a heading
    ///   rather than a unit. A literal counts as a symbol when it is short and
    ///   holds no spaces; anything wordier is a caption and says nothing.
    /// - `_` means *skip the width of the next character*, so `#,##0_)_%` displays
    ///   no percentage at all — the `%` is padding. Reading it as one turns a
    ///   plain number format into a proportion, and a currency format that pads
    ///   the same way into a row that contradicts itself. 39 cells in the fixture
    ///   are written that way.
    ///
    /// - Parameter format: The format string as the file states it.
    /// - Returns: The dimension, or `nil` when the format states none. A
    ///   proportion is reported as ``UnitKind/ratio``; only ``unit(format:label:)``
    ///   can sharpen it to a rate.
    public static func dimension(of format: String?) -> UnitKind? {
        guard let format, format != "General" else { return nil }
        let shown = displayed(in: format)
        let symbols = symbolLiterals(of: format)

        // `[$$-409]` is Excel's locale-qualified currency, and the bracket sits
        // outside any literal.
        if shown.contains("$") || shown.contains("¤") || symbols.contains("$") { return .money }
        if shown.contains("%") || symbols.contains("%") { return .ratio }
        if shown.lowercased().contains("x") || symbols.lowercased().contains("x") { return .ratio }
        if periodWords.contains(where: { literals(of: format).contains($0) }) { return .duration }
        return nil
    }

    /// The unit a single cell's format and label state together.
    ///
    /// - Parameters:
    ///   - format: The cell's number format.
    ///   - label: The account's label.
    /// - Returns: The unit, or `nil` when the format states no dimension.
    public static func unit(format: String?, label: String) -> UnitKind? {
        guard let dimension = dimension(of: format) else { return nil }
        guard dimension == .ratio, isPerPeriod(label) else { return dimension }
        return .rate
    }

    /// The unit an account's cells agree on.
    ///
    /// Cells stating nothing are ignored rather than counted against the ones that
    /// speak: silence is not disagreement, and a row with one formatted cell and
    /// five plain ones has still told us something.
    ///
    /// - Parameters:
    ///   - formats: The formats of the account's cells, in any order.
    ///   - label: The account's label.
    /// - Returns: The unit and, when the cells disagreed, the dimensions found.
    public static func infer(formats: [String?], label: String) -> Inferred {
        var found: [UnitKind] = []
        for format in formats {
            guard let dimension = dimension(of: format) else { continue }
            if !found.contains(dimension) { found.append(dimension) }
        }

        guard let only = found.first else { return Inferred(unit: nil, conflicted: []) }
        guard found.count == 1 else {
            return Inferred(unit: nil, conflicted: found)
        }
        guard only == .ratio, isPerPeriod(label) else {
            return Inferred(unit: only, conflicted: [])
        }
        return Inferred(unit: .rate, conflicted: [])
    }

    // MARK: - Private

    /// Words that make a proportion a rate rather than a ratio.
    ///
    /// Deliberately short. Each is a word that says *per period* in a financial
    /// model and means little else; a longer list would start guessing, and the
    /// cost of guessing wrong here is a false claim where a true one was available.
    private static let perPeriodWords = ["rate", "growth", "yield", "p.a.", "per annum", "coupon"]

    /// Words a format uses to name a period.
    private static let periodWords = ["year", "yr", "month", "quarter", "day", "period"]

    private static func isPerPeriod(_ label: String) -> Bool {
        let lowered = label.lowercased()
        return perPeriodWords.contains { lowered.contains($0) }
    }

    /// What a format actually displays, outside its quoted literals.
    ///
    /// `\\x` shows an `x`; `_x` shows a space as wide as an `x` and so shows
    /// nothing. Treating the two alike is the difference between reading
    /// `#,##0_)_%` as a percentage and reading it as the plain number it is.
    private static func displayed(in format: String) -> String {
        var shown = ""
        var inLiteral = false
        var pending: Character?
        for character in format {
            if let marker = pending {
                if marker == "\\", !inLiteral { shown.append(character) }
                pending = nil
                continue
            }
            switch character {
            case "\"":
                inLiteral.toggle()

            // Both are skip markers, and neither means anything inside a literal.
            // Written as one `where` clause these do not behave alike: the guard
            // binds to the last pattern only, so a backslash inside a literal would
            // set `pending` and then swallow the next character — which can be the
            // closing quote, ending the literal a character early.
            case "\\", "_":
                if !inLiteral { pending = character }

            default:
                if !inLiteral { shown.append(character) }
            }
        }
        return shown
    }

    /// The format's literals that are symbols rather than captions.
    ///
    /// `"$"` and `"x"` state a unit. `"$ in millions"` and `"100% owned"` are
    /// captions that happen to contain the same characters, and a caption is a
    /// note to a reader rather than a claim about the number.
    private static func symbolLiterals(of format: String) -> String {
        var symbols = ""
        var inLiteral = false
        var current = ""
        for character in format {
            if character == "\"" {
                if inLiteral {
                    let trimmed = current.trimmingCharacters(in: .whitespaces)
                    if trimmed.count <= 2, !trimmed.contains(" ") { symbols += trimmed }
                    current = ""
                }
                inLiteral.toggle()
                continue
            }
            if inLiteral { current.append(character) }
        }
        return symbols
    }

    /// The contents of a format's quoted literals, lowercased.
    private static func literals(of format: String) -> String {
        var inside = ""
        var inLiteral = false
        for character in format {
            if character == "\"" { inLiteral.toggle(); continue }
            if inLiteral { inside.append(character) }
        }
        return inside.lowercased()
    }
}
