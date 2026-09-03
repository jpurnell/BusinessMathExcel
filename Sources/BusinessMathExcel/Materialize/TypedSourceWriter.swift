import Foundation
import BusinessMath

/// Emits a recognized workbook as Swift source.
///
/// ## Why source rather than a model
///
/// ``ModelMaterializer`` already turns a plan into something that runs, which is
/// the right answer for a tool. It is the wrong answer for a person, who wants to
/// *read* what the sheet said, keep it under version control, review a diff of it,
/// and have a compiler check it. Emitted source is the artifact that survives the
/// spreadsheet it came from.
///
/// ## The bar
///
/// Not "looks plausible". **Source that does not compile is worse than none**, and
/// source that compiles but computes differently is worse still. Every rule below
/// exists to keep the writer from emitting something the build would reject.
///
/// ## Typed where the sheet said enough, untyped where it did not
///
/// A definition is emitted in the typed vocabulary — `LineItem<Money>`,
/// `revenue.expr * margin.expr` — only when three things hold: every account it
/// reads has a known unit, every operation is one the algebra has an overload for,
/// and the result's unit matches the account being defined.
///
/// Anything else is emitted through the **string API**, which makes no claim. A
/// line of the generated file looks like this — it is output rather than an
/// example to copy, and it compiles where it lands, against BusinessMath:
///
/// ```
/// importedModel = importedModel.defining("Total FCF", as: "([EBITDA] - [Less: Taxes])")
/// ```
///
/// That is not a fallback to be embarrassed about. `LineItem<U>` has no untyped
/// form, so an account whose unit the workbook never stated cannot be given one
/// without inventing it — and sixteen of the Wharton sheet's forty-six accounts
/// state no unit, which makes this the common case on real input rather than a
/// corner. The two spellings mix freely in one model, which is what the string API
/// is for.
///
/// An expression reading one typed and one untyped account goes out untyped
/// **whole**, rather than half-cast into something that would not build.
public enum TypedSourceWriter {

    /// Emits a plan as Swift source.
    ///
    /// - Parameters:
    ///   - model: The recognized plan.
    ///   - sheetName: The worksheet the plan came from, for provenance comments.
    ///   - modelName: The enum the emitted model is namespaced under.
    /// - Returns: Swift source, ready to compile against BusinessMath.
    ///
    /// The file declares an `enum` of static members rather than top-level code.
    /// Top-level statements are legal only in `main.swift`, so a file of them
    /// cannot be compiled into a library or a test target — which is where a
    /// generated model belongs. The namespace also keeps two imported sheets from
    /// colliding on `periods` or `inputs` when both are compiled together.
    public static func swiftSource(
        for model: RecognizedModel,
        sheetName: String = "Sheet1",
        modelName: String = "ImportedModel"
    ) -> String {
        // A rollforward's opening account is real — the driver supplies it every
        // period — but nothing in the plan declares it, so it has no unit of its
        // own. It necessarily has the unit of the account it carries from: an
        // opening balance and the closing balance it becomes are the same
        // quantity at two moments. Inferring that is sound rather than a guess,
        // and without it every definition reading an opening balance falls
        // untyped, which on a debt schedule is most of them.
        var units = Dictionary(
            model.accounts.map { ($0.name, $0.unit) }, uniquingKeysWith: { first, _ in first })
        var declarable = model.accounts
        for carry in model.rollforwards where units[carry.opening] == nil {
            guard let closing = model.accounts.first(where: { $0.name == carry.closing }),
                  let unit = closing.unit
            else { continue }
            units[carry.opening] = unit
            declarable.append(
                RecognizedAccount(
                    name: carry.opening, unit: unit, provenance: [carry.seedCell]))
        }
        let identifiers = identifiers(for: declarable)

        let namespace = typeName(modelName)

        var lines: [String] = []
        lines.append("// Generated from \(sheetName) by BusinessMathExcel.")
        lines.append("//")
        lines.append("// Each declaration names the cell it came from. That is the only way to")
        lines.append("// check this file against the workbook by hand, which is the first thing")
        lines.append("// anyone reading it will want to do.")
        lines.append("")
        lines.append("import BusinessMath")
        lines.append("import Foundation")
        lines.append("")
        lines.append("/// The model recognized from \(sheetName).")
        lines.append("enum \(namespace) {")
        lines.append("")

        var body: [String] = []
        body.append(contentsOf: timeline(model))
        body.append(contentsOf: handles(declarable, identifiers: identifiers,
                                        sheetName: sheetName))
        body.append(contentsOf: inputs(model, sheetName: sheetName))
        body.append(contentsOf: definitions(model, units: units, identifiers: identifiers,
                                            sheetName: sheetName))
        body.append(contentsOf: run(model))

        lines.append(contentsOf: body.map { $0.isEmpty ? "" : "    " + $0 })
        lines.append("}")

        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Sections

    private static func timeline(_ model: RecognizedModel) -> [String] {
        var lines = ["// MARK: - Timeline", ""]
        let periods = model.periods.map { literal(for: $0) }.joined(separator: ",\n    ")
        lines.append("static let periods: [Period] = [\n    \(periods),\n]")
        lines.append("")
        return lines
    }

    private static func handles(
        _ accounts: [RecognizedAccount],
        identifiers: [String: String],
        sheetName: String
    ) -> [String] {
        let typed = accounts.filter { $0.unit != nil }
        guard !typed.isEmpty else { return [] }

        var lines = ["// MARK: - Line items", ""]
        for account in typed {
            guard let unit = account.unit, let identifier = identifiers[account.name] else {
                continue
            }
            lines.append(
                "static let \(identifier) = "
                    + "LineItem<\(swiftUnit(unit))>(\(quoted(account.name)))"
                    + "  \(provenance(account, sheetName: sheetName))")
        }
        lines.append("")
        return lines
    }

    private static func inputs(_ model: RecognizedModel, sheetName: String) -> [String] {
        let supplied = model.accounts.filter { $0.values != nil }
        guard !supplied.isEmpty else { return [] }

        var lines = [
            "// MARK: - Data", "", "static let inputs: [String: TimeSeries<Double>] = [",
        ]
        for account in supplied {
            guard let values = account.values else { continue }
            let ordered = model.periods.filter { values[$0] != nil }
            let series = ordered.compactMap { values[$0] }.map { "\($0)" }
                .joined(separator: ", ")
            let periodList = ordered.map { literal(for: $0) }.joined(separator: ", ")
            lines.append(
                "    \(quoted(account.name)): TimeSeries(periods: [\(periodList)], "
                    + "values: [\(series)]),  \(provenance(account, sheetName: sheetName))")
        }
        lines.append("]")
        lines.append("")
        return lines
    }

    private static func definitions(
        _ model: RecognizedModel,
        units: [String: UnitKind?],
        identifiers: [String: String],
        sheetName: String
    ) -> [String] {
        var lines = ["// MARK: - Definitions", ""]
        lines.append("/// The model as the sheet defines it.")
        lines.append("static func definition() -> ModelDefinition<Double> {")
        lines.append("    var model = ModelDefinition<Double>(inputs: inputs)")

        for account in model.accounts {
            guard let expression = account.expression else { continue }
            let mark = provenance(account, sheetName: sheetName)

            if let unit = account.unit,
               let identifier = identifiers[account.name],
               let rendered = typedExpression(
                expression, expecting: unit, units: units, identifiers: identifiers) {
                lines.append("    model = model.defining(\(identifier), as: \(rendered))")
                lines.append("        \(mark)")
            } else {
                lines.append(
                    "    model = model.defining("
                        + "\(quoted(account.name)), as: \(quoted(expression.rendered())))")
                lines.append("        \(mark)")
            }
        }
        lines.append("    return model")
        lines.append("}")
        lines.append("")
        return lines
    }

    private static func run(_ model: RecognizedModel) -> [String] {
        var lines = ["// MARK: - Running", ""]
        lines.append("/// Every account, supplied and derived, over the timeline.")
        lines.append("static func run() throws -> [String: TimeSeries<Double>] {")
        lines.append("    let model = definition()")
        lines.append("    try model.validateUnits()")

        guard !model.rollforwards.isEmpty else {
            lines.append("    return try model.solve()")
            lines.append("}")
            return lines
        }

        lines.append("")
        lines.append("    let driver = PeriodDriver(")
        lines.append("        definition: model,")
        lines.append("        rollforwards: [")
        for carry in model.rollforwards {
            lines.append(
                "            Rollforward(opening: \(quoted(carry.opening)), "
                    + "closing: \(quoted(carry.closing)), seed: \(carry.seed)),")
        }
        lines.append("        ]")
        lines.append("    )")
        lines.append("    return try driver.run(over: periods)")
        lines.append("}")
        return lines
    }

    /// A model name as a legal Swift type name.
    ///
    /// A name that is already a legal identifier is kept as the caller wrote it,
    /// with only its first letter raised. Running it through ``camelCased(_:)``
    /// would flatten the caller's own casing — `GoldenForecast` has no separators
    /// to split on, so it would come back as one lowercased word.
    ///
    /// - Parameter name: The requested name.
    /// - Returns: The name, as a type name.
    private static func typeName(_ name: String) -> String {
        let alreadyLegal = !name.isEmpty
            && name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
            && !(name.first?.isNumber ?? true)
        let identifier = alreadyLegal ? name : camelCased(name)
        guard let first = identifier.first else { return "ImportedModel" }
        return first.uppercased() + identifier.dropFirst()
    }

    // MARK: - Typed expressions

    /// An expression in the typed vocabulary, or `nil` when it cannot be one.
    ///
    /// Returns `nil` rather than approximating. Every path that cannot be written
    /// with an overload the algebra actually has — an unknown unit, a comparison,
    /// a function outside `MIN`/`MAX`/`ABS`, a combination with no overload — sends
    /// the whole definition to the string API, which is the only spelling that
    /// makes no claim.
    private static func typedExpression(
        _ expression: RecognizedExpression,
        expecting unit: UnitKind,
        units: [String: UnitKind?],
        identifiers: [String: String]
    ) -> String? {
        guard let inferred = self.unit(of: expression, units: units), inferred == unit else {
            return nil
        }
        return render(expression, units: units, identifiers: identifiers)
    }

    /// The unit an expression yields, or `nil` if the algebra cannot express it.
    ///
    /// A bare number is a ``UnitKind/ratio``: dimensionless is what a number in a
    /// formula is unless something says otherwise, and calling it a rate would be
    /// a claim about periodicity the sheet never made.
    private static func unit(
        of expression: RecognizedExpression, units: [String: UnitKind?]
    ) -> UnitKind? {
        switch expression {
        case .account(let name):
            guard let known = units[name], let unit = known else { return nil }
            return unit

        case .number:
            return .ratio

        case .negated(let operand):
            return self.unit(of: operand, units: units)

        case .binary(let op, let lhs, let rhs):
            guard let left = self.unit(of: lhs, units: units),
                  let right = self.unit(of: rhs, units: units)
            else { return nil }
            return result(of: op, left, right)

        case .call(let name, let arguments):
            // The typed layer has `min`, `max` and `abs`. Nothing else, so nothing
            // else can be emitted typed.
            guard ["MIN", "MAX", "ABS"].contains(name) else { return nil }
            let inferred = arguments.compactMap { self.unit(of: $0, units: units) }
            guard inferred.count == arguments.count, let first = inferred.first,
                  inferred.allSatisfy({ $0 == first })
            else { return nil }
            return first

        case .list, .refused:
            return nil
        }
    }

    /// The unit a binary operation yields, or `nil` where there is no overload.
    ///
    /// This mirrors the overloads in BusinessMath's `Expr`. A combination absent
    /// here is absent there, and emitting it would produce source that does not
    /// build.
    private static func result(
        of op: RecognizedExpression.Operator, _ lhs: UnitKind, _ rhs: UnitKind
    ) -> UnitKind? {
        switch op {
        case .add, .subtract:
            return lhs == rhs ? lhs : nil

        case .multiply:
            switch (lhs, rhs) {
            case (.money, .ratio), (.ratio, .money), (.money, .rate), (.rate, .money):
                return .money
            case (.ratio, .ratio):
                return .ratio
            default:
                return nil
            }

        case .divide:
            switch (lhs, rhs) {
            case (.money, .money): return .ratio
            case (.money, .duration), (.money, .ratio): return .money
            case (.ratio, .ratio): return .ratio
            default: return nil
            }

        case .equal, .notEqual, .greaterThan, .lessThan, .greaterOrEqual, .lessOrEqual:
            // No comparison overloads upstream, and no unit for a condition.
            return nil
        }
    }

    private static func render(
        _ expression: RecognizedExpression,
        units: [String: UnitKind?],
        identifiers: [String: String]
    ) -> String {
        switch expression {
        case .account(let name):
            return "\(identifiers[name] ?? name).expr"

        case .number(let value):
            return "ratio(\(value))"

        case .negated(let operand):
            return "-\(render(operand, units: units, identifiers: identifiers))"

        case .binary(let op, let lhs, let rhs):
            let left = render(lhs, units: units, identifiers: identifiers)
            let right = render(rhs, units: units, identifiers: identifiers)
            return "(\(left) \(op.rawValue) \(right))"

        case .call(let name, let arguments):
            let rendered = arguments
                .map { render($0, units: units, identifiers: identifiers) }
                .joined(separator: ", ")
            return "\(name.lowercased())(\(rendered))"

        case .list, .refused:
            // Unreachable: `unit(of:)` refuses both, so nothing reaches here.
            return "ratio(0)"
        }
    }

    // MARK: - Naming

    /// A Swift identifier per account, unique across the file.
    ///
    /// Account names come from a spreadsheet, so they carry spaces, punctuation,
    /// leading digits and case differences that Swift does not. Two accounts can
    /// also collapse to one identifier — `Interest` and `interest` — and both have
    /// to exist, so a collision is numbered rather than dropped.
    private static func identifiers(for accounts: [RecognizedAccount]) -> [String: String] {
        var assigned: [String: String] = [:]
        var used: Set<String> = []

        for account in accounts {
            var candidate = camelCased(account.name)
            if candidate.isEmpty { candidate = "account" }
            if keywords.contains(candidate) { candidate = "`\(candidate)`" }

            var unique = candidate
            var suffix = 2
            while used.contains(unique) {
                unique = candidate.hasPrefix("`")
                    ? "`\(candidate.dropFirst().dropLast())\(suffix)`"
                    : "\(candidate)\(suffix)"
                suffix += 1
            }
            used.insert(unique)
            assigned[account.name] = unique
        }
        return assigned
    }

    /// A name as a camel-cased identifier, with any leading digits moved to the end.
    ///
    /// `2023 Revenue` cannot begin an identifier, and dropping the year would lose
    /// what distinguishes it from every other revenue line, so it becomes
    /// `revenue2023`.
    private static func camelCased(_ name: String) -> String {
        let words = name
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
        guard !words.isEmpty else { return "" }

        let leadingNumbers = words.prefix { $0.allSatisfy(\.isNumber) }
        let rest = Array(words.dropFirst(leadingNumbers.count))
        let ordered = rest.isEmpty ? Array(leadingNumbers) : rest + Array(leadingNumbers)

        var identifier = ""
        for (index, word) in ordered.enumerated() {
            if index == 0 {
                identifier += word.lowercased()
            } else if word.allSatisfy(\.isNumber) {
                identifier += word
            } else {
                identifier += word.prefix(1).uppercased() + word.dropFirst().lowercased()
            }
        }
        return identifier.first?.isNumber == true ? "account\(identifier)" : identifier
    }

    private static let keywords: Set<String> = [
        "return", "class", "struct", "enum", "protocol", "extension", "func", "var", "let",
        "if", "else", "for", "while", "switch", "case", "default", "break", "continue",
        "import", "init", "self", "super", "true", "false", "nil", "in", "is", "as", "try",
        "throw", "throws", "catch", "defer", "guard", "repeat", "where", "operator", "static",
        "public", "private", "internal", "open", "final", "lazy", "weak", "inout", "some", "any",
    ]

    // MARK: - Fragments

    private static func provenance(_ account: RecognizedAccount, sheetName: String) -> String {
        // The anchor first, since that is the cell a reader would look at to check
        // the account against the sheet.
        guard let cell = account.provenance.first else { return "" }
        return "// \(sheetName)!\(cell.reference)"
    }

    private static func swiftUnit(_ unit: UnitKind) -> String {
        switch unit {
        case .money: return "Money"
        case .rate: return "Rate"
        case .ratio: return "Ratio"
        // `Count` upstream. The standard library owns `Duration`, so BusinessMath
        // could not use it and neither can what we emit.
        case .duration: return "Count"
        }
    }

    private static func literal(for period: Period) -> String {
        switch period.type {
        case .annual:
            return "Period.year(\(Calendar(identifier: .gregorian).component(.year, from: period.date)))"
        default:
            let calendar = Calendar(identifier: .gregorian)
            let year = calendar.component(.year, from: period.date)
            let month = calendar.component(.month, from: period.date)
            return "Period.month(year: \(year), month: \(month))"
        }
    }

    private static func quoted(_ text: String) -> String {
        "\"\(text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
    }
}
