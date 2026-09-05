import SwiftXLSX

/// Whether a series' cells share a single formula shape across the timeline.
///
/// `ModelDefinition` holds **one formula per account**, applied to every period.
/// So a series only becomes an account if every cell in it computes the same way,
/// differing only by which period it looks at. Per-period *values* vary freely;
/// per-period *shape* does not.
///
/// The count of series that fail this is the number worth having. It measures how
/// much of a sheet has been hand-edited away from its own pattern, and therefore
/// how much of it can be expressed as accounts at all.
///
/// ## How two cells are compared
///
/// Each formula is canonicalized relative to the cell holding it: every reference
/// becomes an offset from that cell rather than an address. Two cells share a
/// shape when those canonical forms are identical. This is the idea behind R1C1
/// notation, and it is the same equivalence Excel uses when it fills a formula
/// across a row.
///
/// Literals inside a formula are part of the shape, deliberately. A row that grows
/// by `1.1` in four periods and `1.2` in the fifth is precisely the hand edit this
/// is looking for, and treating the constant as incidental would hide it.
///
/// A row of plain values is uniform: its shape is "a literal per period", and the
/// values themselves are free to differ. A row mixing values and formulas is not —
/// a typed first period followed by computed ones is a seed plus a rollforward,
/// which is two shapes, and reporting it as one would be a false simplification.
///
/// ## What it will not do
///
/// **It never picks a majority shape.** Two cells agreeing and one not is a sheet
/// with a hand edit in it, not a sheet with a shape and a typo. Adopting the
/// majority would rewrite the outlier into something the author did not write.
public struct FormulaUniformity: Sendable {

    /// How a series' cells relate to one another.
    public enum Kind: Sendable, Equatable {

        /// Every populated cell shares one shape.
        case uniform

        /// The first period differs; every period after it shares one shape.
        ///
        /// The commonest structure in a financial model, and an expressible one:
        /// a typed or separately-derived opening value, then a rule applied
        /// forward. It is not a hand edit, and counting it as one would badly
        /// overstate how much of a sheet resists being expressed as accounts.
        case seededRollforward

        /// The periods after the first disagree among themselves.
        ///
        /// This is the hand edit — someone overtyped a cell in the middle of a
        /// row — and the count of these is the number worth reporting.
        case nonUniform
    }

    /// The series assessed.
    public let series: LabeledSeries

    /// How the series' cells relate.
    public let kind: Kind

    /// Whether every populated cell shares one shape.
    public var isUniform: Bool { kind == .uniform }

    /// The shared canonical shape, or `nil` when the cells disagree.
    ///
    /// Always `nil` when ``isUniform`` is false: no shape is adopted from a
    /// disagreement.
    public let shape: String?

    /// The cells whose shape differs from the first one seen.
    public let divergentCells: [CellRef]

    // MARK: - Assessing

    /// Assesses every series on a sheet.
    ///
    /// - Parameters:
    ///   - series: The bound series.
    ///   - grid: The sheet's topology, for cell contents and node positions.
    /// - Returns: One report per series, plus a
    ///   ``DiagnosticCode/nonUniformRow`` for each series that disagrees with
    ///   itself, naming the first cell that broke it.
    public static func assess(
        _ series: [LabeledSeries],
        in grid: SheetGrid
    ) -> (report: [FormulaUniformity], diagnostics: [Diagnostic]) {
        var report: [FormulaUniformity] = []
        var diagnostics: [Diagnostic] = []

        for entry in series {
            var baseline: String?
            var divergent: [CellRef] = []

            for cell in entry.populatedCells {
                guard let kind = grid.cells[cell] else { continue }
                let shape = canonicalShape(of: kind, at: cell, in: grid)
                guard let baseline else {
                    baseline = shape
                    continue
                }
                if shape != baseline { divergent.append(cell) }
            }

            let kind: Kind
            if divergent.isEmpty {
                kind = .uniform
            } else if isSeededRollforward(entry, divergent: divergent, in: grid) {
                kind = .seededRollforward
            } else {
                kind = .nonUniform
            }

            report.append(
                FormulaUniformity(
                    series: entry,
                    kind: kind,
                    shape: kind == .uniform ? baseline : nil,
                    divergentCells: divergent
                )
            )

            // Only a genuine disagreement is reported. A seeded rollforward is a
            // structure the model layer expresses directly, not a defect.
            if kind == .nonUniform, let first = divergent.first {
                diagnostics.append(
                    Diagnostic(
                        severity: .warning, code: .nonUniformRow, cell: first,
                        message: "\"\(entry.name)\" does not compute the same way in every "
                            + "period; \(first.reference) differs from the periods around it"))
            }
        }

        return (report, diagnostics)
    }

    /// Whether the only disagreement is that the first period differs.
    ///
    /// True when every populated cell from the second onward shares one shape.
    /// Establishes the pattern from the second period rather than the first,
    /// which is the whole point: the first is the seed.
    private static func isSeededRollforward(
        _ series: LabeledSeries, divergent: [CellRef], in grid: SheetGrid
    ) -> Bool {
        let populated = series.populatedCells
        guard populated.count >= 3 else { return false }

        let afterSeed = populated.dropFirst()
        guard divergent.allSatisfy({ afterSeed.contains($0) }) else { return false }

        var baseline: String?
        for cell in afterSeed {
            guard let kind = grid.cells[cell] else { continue }
            let shape = canonicalShape(of: kind, at: cell, in: grid)
            guard let baseline else {
                baseline = shape
                continue
            }
            if shape != baseline { return false }
        }
        return baseline != nil
    }

    // MARK: - Private

    /// A cell's shape, in R1C1 terms relative to the cell holding it.
    private static func canonicalShape(
        of kind: NodeKind, at cell: CellRef, in grid: SheetGrid
    ) -> String {
        switch kind {
        case .input:
            // A literal. Its value is free to vary period to period.
            return "#num"
        case .textInput, .label:
            return "#text"
        case .formula(let formula), .output(let formula):
            // The file's own AST when we have it, because only that records
            // whether a reference was written `D14` or `$D$14` — the distinction
            // that decides whether two cells hold the same formula filled across.
            if let ast = grid.formulaASTs[cell] {
                return canonicalShape(of: ast, at: cell)
            }
            return canonicalShape(of: formula, at: cell, in: grid)
        }
    }

    /// A formula's shape in R1C1 terms: relative references become offsets from
    /// the cell holding them, absolute references keep their fixed address.
    ///
    /// This is precisely the equivalence Excel uses when filling a formula, which
    /// is why `$D$14 * -1` repeated across five periods is one shape rather than
    /// five, and why treating the `$` as decoration would report an untouched row
    /// as hand-edited.
    /// A formula's shape in R1C1 form, relative to the cell holding it.
    ///
    /// Shared with ``ShapeRun``, which asks the same question for a different
    /// purpose: this type asks whether a *bound row* computes one way, and that one
    /// asks which cells compute alike when nothing has been bound yet. Two
    /// canonicalisers would eventually disagree about what "the same shape" means,
    /// and the disagreement would be invisible until a row was uniform to one and
    /// not the other.
    ///
    /// - Parameters:
    ///   - ast: The formula.
    ///   - cell: The cell holding it, which the addresses are relative to.
    /// - Returns: The canonical shape.
    static func canonicalShape(of ast: FormulaAST, at cell: CellRef) -> String {
        func each(_ operands: FormulaAST...) -> String {
            operands.map { canonicalShape(of: $0, at: cell) }.joined(separator: ",")
        }

        switch ast {
        case .cellRef(let ref):
            return address(of: ref, from: cell)
        case .cellRange(let range):
            return "range(\(address(of: range.start, from: cell))"
                + ":\(address(of: range.end, from: cell)))"
        case .sheetRef(let reference):
            // Relative to the referring cell, exactly as a same-sheet reference is.
            // A cross-sheet reference fills across like any other, so rendering its
            // absolute address made every cell in the row a different shape — and a
            // row that disagrees with itself is refused. On a model that keeps its
            // data on one sheet and its arithmetic on another, that is every row.
            return "sheet(\(reference.sheetName)!"
                + "\(address(of: reference.range.start, from: cell))"
                + ":\(address(of: reference.range.end, from: cell)))"
        case .namedRange(let name):
            return "name(\(name))"
        case .number(let value):
            return "\(value)"
        case .text(let value):
            return "t(\(value))"
        case .bool(let value):
            return "b(\(value))"
        case .error(let value):
            return "err(\(value.rawValue))"
        case .missing:
            // A stable token, because two cells that both omit the same argument
            // compute the same way — which is what a shape run is for. `IFERROR(x,)`
            // filled across a row is one rule, not a row of exceptions.
            return "miss()"
        case .add(let lhs, let rhs): return "add(\(each(lhs, rhs)))"
        case .subtract(let lhs, let rhs): return "sub(\(each(lhs, rhs)))"
        case .multiply(let lhs, let rhs): return "mul(\(each(lhs, rhs)))"
        case .divide(let lhs, let rhs): return "div(\(each(lhs, rhs)))"
        case .power(let lhs, let rhs): return "pow(\(each(lhs, rhs)))"
        case .concatenate(let lhs, let rhs): return "cat(\(each(lhs, rhs)))"
        case .negate(let expr): return "neg(\(each(expr)))"
        case .equal(let lhs, let rhs): return "eq(\(each(lhs, rhs)))"
        case .notEqual(let lhs, let rhs): return "ne(\(each(lhs, rhs)))"
        case .greaterThan(let lhs, let rhs): return "gt(\(each(lhs, rhs)))"
        case .lessThan(let lhs, let rhs): return "lt(\(each(lhs, rhs)))"
        case .greaterOrEqual(let lhs, let rhs): return "ge(\(each(lhs, rhs)))"
        case .lessOrEqual(let lhs, let rhs): return "le(\(each(lhs, rhs)))"
        case .function(let name, let args):
            return "\(name)(\(args.map { canonicalShape(of: $0, at: cell) }.joined(separator: ",")))"
        }
    }

    /// One reference in R1C1 terms: pinned components keep their address, free
    /// components become an offset.
    private static func address(of ref: CellRef, from cell: CellRef) -> String {
        let row = ref.absoluteRow ? "R$\(ref.row)" : "R\(ref.row - cell.row)"
        let column = ref.absoluteColumn ? "C$\(ref.column)" : "C\(ref.column - cell.column)"
        return row + column
    }

    private static func canonicalShape(
        of formula: NodeFormula, at cell: CellRef, in grid: SheetGrid
    ) -> String {
        func each(_ operands: NodeFormula...) -> String {
            operands.map { canonicalShape(of: $0, at: cell, in: grid) }.joined(separator: ",")
        }

        switch formula {
        case .ref(let node):
            return offset(of: node, from: cell, in: grid)
        case .number(let value):
            return "\(value)"
        case .text(let value):
            return "t(\(value))"
        case .bool(let value):
            return "b(\(value))"
        case .range(let nodes):
            return "range(\(nodes.map { offset(of: $0, from: cell, in: grid) }.joined(separator: ",")))"
        case .add(let lhs, let rhs): return "add(\(each(lhs, rhs)))"
        case .subtract(let lhs, let rhs): return "sub(\(each(lhs, rhs)))"
        case .multiply(let lhs, let rhs): return "mul(\(each(lhs, rhs)))"
        case .divide(let lhs, let rhs): return "div(\(each(lhs, rhs)))"
        case .power(let lhs, let rhs): return "pow(\(each(lhs, rhs)))"
        case .negate(let expr): return "neg(\(each(expr)))"
        case .equal(let lhs, let rhs): return "eq(\(each(lhs, rhs)))"
        case .notEqual(let lhs, let rhs): return "ne(\(each(lhs, rhs)))"
        case .greaterThan(let lhs, let rhs): return "gt(\(each(lhs, rhs)))"
        case .lessThan(let lhs, let rhs): return "lt(\(each(lhs, rhs)))"
        case .greaterOrEqual(let lhs, let rhs): return "ge(\(each(lhs, rhs)))"
        case .lessOrEqual(let lhs, let rhs): return "le(\(each(lhs, rhs)))"
        case .function(let name, let args):
            let rendered = args.map { canonicalShape(of: $0, at: cell, in: grid) }
            return "\(name)(\(rendered.joined(separator: ",")))"
        }
    }

    /// A reference rendered as its offset from the referring cell.
    ///
    /// Two cells one column apart that each look one row up are the same shape;
    /// their absolute addresses are not.
    private static func offset(of node: NodeRef, from cell: CellRef, in grid: SheetGrid) -> String {
        guard let target = grid.nodeToCell[node] else { return "?" }
        return "R\(target.row - cell.row)C\(target.column - cell.column)"
    }
}
