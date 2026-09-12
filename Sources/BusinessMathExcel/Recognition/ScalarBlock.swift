import SwiftXLSX

/// A label bound to the single value it names, outside the timeline.
///
/// The counterpart to ``LabeledSeries``. A series is a label with one value per
/// period; an assumption is a label with one value full stop — a tax rate, an
/// entry multiple, an opening revenue figure. Both are accounts; only one has a
/// timeline.
public struct ScalarAssumption: Sendable, Equatable {

    /// The assumption's name, read from its label.
    public let name: String

    /// The cell the name was read from.
    public let labelCell: CellRef

    /// The cell holding the value, which may be a literal or a formula.
    public let valueCell: CellRef

    /// Creates an assumption.
    ///
    /// - Parameters:
    ///   - name: The assumption's name.
    ///   - labelCell: Where the name was read from.
    ///   - valueCell: Where the value sits.
    public init(name: String, labelCell: CellRef, valueCell: CellRef) {
        self.name = name
        self.labelCell = labelCell
        self.valueCell = valueCell
    }
}

/// Stage 2b — the assumptions a sheet states outside its timeline.
///
/// ## Why a sheet has more than one block
///
/// ``PeriodAxis`` finds where the timeline is. It is tempting to conclude the
/// sheet *is* that timeline, and every real model says otherwise: above the model
/// sits a block of assumptions, usually two or three small tables side by side,
/// each a label with its figure beside it. Those tables know nothing of the years
/// below them, and their value columns land wherever the page was laid out —
/// including, on the Wharton `ANSWER KEY`, squarely in the timeline's columns.
///
/// Two things follow from treating them as their own block.
///
/// The **anchor column carries no meaning here**. Column `D` is the at-close
/// column *for the timeline*, holding an opening balance or an equity cheque
/// written before the first year. Sixteen rows higher it is just the column the
/// assumptions happened to be typed into, and reading `100` as an at-close figure
/// rather than as this year's revenue is the same mistake in a different place.
///
/// An assumption **holds for every period**. `Revenue growth` is 10% in all six
/// years, not in one of them, so it materializes as an input repeated across the
/// timeline. Anything referencing it then resolves — which is the whole reason
/// this type exists, because without it a sheet loses the assumptions its model
/// is built on and cannot be run at all.
///
/// ## What is not an assumption
///
/// A heading owns no value and yields nothing; `Assumptions` and
/// `Purchase Price Analysis` are titles, and inventing a figure for them would be
/// worse than leaving them unrecognized. A label owning *several* values is not an
/// assumption either — that is a row of some other kind, most often a header — and
/// it is reported rather than collapsed to its first figure.
public enum ScalarBlock {

    /// Binds every assumption stated outside the timeline block.
    ///
    /// - Parameters:
    ///   - grid: The sheet's topology, with an established orientation.
    ///   - axis: The recovered time axis, whose heading line bounds the block.
    /// - Returns: One assumption per label owning exactly one value, plus
    ///   diagnostics for labels owning more than one.
    public static func bind(
        in grid: SheetGrid,
        axis: PeriodAxis
    ) -> (scalars: [ScalarAssumption], diagnostics: [Diagnostic]) {
        guard let orientation = grid.orientation, let axisLine = grid.axisLine else {
            return ([], [])
        }

        var diagnostics: [Diagnostic] = []
        var scalars: [ScalarAssumption] = []
        var usedNames: Set<String> = []
        let whatIf = DataTableBlock.find(in: grid)

        for line in lines(in: grid, orientation: orientation).sorted() where line < axisLine {
            for (labelCell, name, owned) in tables(
                on: line, in: grid, orientation: orientation, excluding: whatIf
            ) {
                // A heading owns nothing and is not a finding — `Assumptions` and
                // `Purchase Price Analysis` are titles. A label owning *several*
                // values is a real ambiguity and is reported.
                guard let only = owned.first, owned.count == 1 else {
                    if owned.count > 1 {
                        diagnostics.append(
                            Diagnostic(
                                severity: .info, code: .ambiguousAssumption,
                                cell: labelCell,
                                message: "\"\(name)\" at \(labelCell.reference) is above the "
                                    + "timeline and owns \(owned.count) values, so it is not "
                                    + "one assumption; it is not recognized rather than being "
                                    + "read as its first figure"))
                    }
                    continue
                }

                var unique = name
                if usedNames.contains(unique) {
                    diagnostics.append(
                        Diagnostic(
                            severity: .warning, code: .duplicateAccountName, cell: labelCell,
                            message: "\"\(name)\" labels more than one assumption; the one at "
                                + "\(labelCell.reference) is distinguished by its cell"))
                    unique = "\(name) (\(labelCell.reference))"
                }
                usedNames.insert(unique)
                scalars.append(
                    ScalarAssumption(name: unique, labelCell: labelCell, valueCell: only))
            }
        }

        return (scalars, diagnostics)
    }

    /// The label/value tables on one line, in order.
    ///
    /// Each text cell opens a table and owns every non-text cell up to the next
    /// text cell — the same nearest-label rule ``LabeledSeries`` binds by, so a
    /// name means the same thing whichever type read it.
    private static func tables(
        on line: Int,
        in grid: SheetGrid,
        orientation: SheetGrid.Orientation,
        excluding whatIf: [DataTableBlock]
    ) -> [(labelCell: CellRef, name: String, owned: [CellRef])] {
        var occupied: [(position: Int, ref: CellRef, text: String?)] = []
        for (ref, kind) in grid.cells {
            let lineOf = orientation == .periodsAcrossColumns ? ref.row : ref.column
            guard lineOf == line else { continue }
            // A What-If table's cells are answers, and the table speaks for them.
            guard !whatIf.contains(where: { $0.contains(ref) }) else { continue }
            let position = orientation == .periodsAcrossColumns ? ref.column : ref.row
            occupied.append((position, ref, LabeledSeries.text(of: kind)))
        }
        occupied.sort { $0.position < $1.position }

        var tables: [(labelCell: CellRef, name: String, owned: [CellRef])] = []
        for entry in occupied {
            if let text = entry.text {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                tables.append((entry.ref, trimmed, []))
            } else if !tables.isEmpty {
                tables[tables.count - 1].owned.append(entry.ref)
            }
        }
        return tables
    }

    /// Every line the sheet has anything on.
    private static func lines(
        in grid: SheetGrid, orientation: SheetGrid.Orientation
    ) -> Set<Int> {
        var lines: Set<Int> = []
        for (ref, _) in grid.cells {
            lines.insert(orientation == .periodsAcrossColumns ? ref.row : ref.column)
        }
        return lines
    }
}
