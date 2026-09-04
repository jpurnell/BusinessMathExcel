import SwiftXLSX

/// What a cell is, according to the edges around it.
///
/// Every cell in a dependency graph answers two questions — *is anything fed into
/// me* and *do I feed anything* — and those two bits have four combinations. They
/// happen to land on the vocabulary modellers already use, which is not a
/// coincidence: a spreadsheet is a dependency graph, and the roles a modeller names
/// are the shapes that graph can take.
///
/// Nothing here is inferred from labels, formats, position, or wording, so nothing
/// here is fitted to the workbooks it was written against. It is the definition of
/// an edge, and it answers on every sheet — including the ones a recognizer looking
/// for a timeline finds nothing in.
public enum GraphRole: String, Sendable, Hashable, CaseIterable {

    /// Fed by nothing, feeding something. What the model is given.
    case parameter

    /// Fed by something, feeding nothing. What the model is for.
    case objective

    /// Fed, and feeding. The work between the two.
    case calculation

    /// Fed by nothing and feeding nothing — part of no computation.
    ///
    /// Mostly captions and headings, and this is where they belong: a title is not
    /// a quantity. But a *number* can land here too, and that is worth seeing
    /// rather than filtering away. A figure nobody reads is a stranded assumption,
    /// a leftover from an older version of the sheet, or a value someone means to
    /// wire up. The graph cannot say which; it can say the cell is orphaned.
    case unreachable
}

/// Every cell of a sheet, sorted by the shape of the graph around it.
///
/// ## What this is not
///
/// Not recognition. ``ExcelRecognizer`` asks whether a sheet is a financial model
/// with a timeline and accounts, and returns nothing when the answer is no. This
/// asks only what the edges say, so it always answers, on any sheet, and produces
/// no residue and no refusals.
///
/// ## What it is for
///
/// A layout is a projection of a graph, and there is more than one. The Tuck
/// Decision Science convention structures a model as *Parameters* → *Decisions* →
/// *Objective* → *Calculation*; another modeller structures it differently. Both
/// are views over the same dependencies, so the grouping cannot live in the graph
/// — it has to be computed from it, which is what this does.
///
/// ## Decisions are missing, deliberately
///
/// There are four roles here and the convention above names five things. A
/// *decision variable* is topologically identical to a parameter: fed by nothing,
/// feeding something. What separates them is that an optimiser changes one of
/// them, and that is not visible in the dependency structure at all.
///
/// So it is not guessed at. Where a workbook states its decisions — Excel records
/// Solver's adjustable cells in defined names — they can be read; where it does
/// not, a decision is reported as the ``GraphRole/parameter`` it is
/// indistinguishable from.
public struct GraphPartition: Sendable {

    /// Every populated cell's role.
    public let roles: [CellAddress: GraphRole]

    /// The cells holding each role, in reading order.
    public let byRole: [GraphRole: [CellAddress]]

    /// The graph the roles were read from.
    ///
    /// Kept rather than discarded: a caller asking *what is this* almost always
    /// asks *what does it read* next, and rebuilding the graph to answer costs
    /// more than carrying it.
    public let graph: DependencyGraph

    /// Sorts a sheet's cells by the shape of the graph around them.
    ///
    /// - Parameters:
    ///   - sheet: The sheet to read.
    ///   - including: Whether a cell belongs in the graph, given its value.
    ///     Defaults to every cell the sheet holds, which is what keeps captions
    ///     visible as ``GraphRole/unreachable`` rather than dropping them.
    public init(sheet: Worksheet, including: ((CellValue) -> Bool)? = nil) {
        self.init(graph: DependencyGraph(sheet: sheet, including: including))
    }

    /// Sorts the cells of a graph already built.
    ///
    /// - Parameter graph: The dependency graph to read.
    public init(graph: DependencyGraph) {
        // `inputs` is every cell with no precedents and `outputs` every cell with
        // no dependents, so a cell in both is in no computation at all. Taking the
        // intersection first is what keeps captions out of the parameters.
        let fedByNothing = Set(graph.inputs)
        let feedingNothing = Set(graph.outputs)

        var roles: [CellAddress: GraphRole] = [:]
        var byRole: [GraphRole: [CellAddress]] = [:]
        for cell in graph.allCells {
            let role: GraphRole
            switch (fedByNothing.contains(cell), feedingNothing.contains(cell)) {
            case (true, true): role = .unreachable
            case (true, false): role = .parameter
            case (false, true): role = .objective
            case (false, false): role = .calculation
            }
            roles[cell] = role
            byRole[role, default: []].append(cell)
        }

        self.roles = roles
        self.byRole = byRole.mapValues { $0.sorted(by: GraphPartition.readingOrder) }
        self.graph = graph
    }

    /// The cells holding one role, in reading order.
    ///
    /// - Parameter role: The role to look up.
    /// - Returns: The cells, or an empty array when the sheet holds none.
    public func cells(_ role: GraphRole) -> [CellAddress] { byRole[role] ?? [] }

    /// How many cells hold each role.
    public var counts: [GraphRole: Int] { byRole.mapValues(\.count) }

    /// Sheet, then down, then across — the order a person reads a workbook in.
    ///
    /// `CellAddress` orders nothing itself, and SwiftXLSX keeps its own sort key
    /// internal, so the order is stated here rather than borrowed.
    private static func readingOrder(_ lhs: CellAddress, _ rhs: CellAddress) -> Bool {
        if lhs.sheet != rhs.sheet { return lhs.sheet < rhs.sheet }
        if lhs.cell.row != rhs.cell.row { return lhs.cell.row < rhs.cell.row }
        return lhs.cell.column < rhs.cell.column
    }
}
