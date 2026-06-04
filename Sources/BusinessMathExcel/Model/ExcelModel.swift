/// The kind of a node in an ``ExcelModel`` graph.
public enum NodeKind: Sendable, Equatable {

    /// An editable numeric input value.
    case input(Double)

    /// An editable text input value.
    case textInput(String)

    /// A computed formula node.
    case formula(NodeFormula)

    /// A highlighted output node (computed from a formula).
    case output(NodeFormula)

    /// A static text label.
    case label(String)
}

/// A named group of related nodes in an ``ExcelModel``.
public struct ModelSection: Sendable {

    /// The name of this section.
    public let name: String

    /// The node references in this section, in insertion order.
    public internal(set) var refs: [NodeRef]
}

/// A table of repeating rows registered in an ``ExcelModel``.
public struct TableRef: Sendable {

    /// The display label for this table.
    public let label: String

    /// Column header names.
    public let columns: [String]

    /// Node references organized as rows (outer) by columns (inner).
    public let rows: [[NodeRef]]

    /// The number of data rows.
    public var rowCount: Int { rows.count }

    /// Returns the node reference at the given row and column indices.
    ///
    /// - Parameters:
    ///   - row: Zero-based row index.
    ///   - column: Zero-based column index.
    /// - Returns: The ``NodeRef`` at that position.
    public func cell(row: Int, column: Int) -> NodeRef {
        rows[row][column]
    }
}

/// A directed acyclic graph of nodes representing an Excel computational model.
///
/// Nodes are identified by ``NodeRef`` and grouped into named sections.
/// Cell positions are not assigned here — they are determined at export time
/// by a layout strategy.
///
/// Build the model by calling the `add*` methods, then pass it to an exporter.
// Justification: construction-only mutation; the model is built once then read by the exporter
public final class ExcelModel: @unchecked Sendable {

    private var nodes: [NodeRef: NodeKind] = [:]
    private var sectionList: [ModelSection] = []
    private var nameIndex: [String: NodeRef] = [:]
    private var tableIndex: [String: TableRef] = [:]

    /// Creates an empty model.
    public init() {}

    /// The total number of nodes in the model.
    public var nodeCount: Int { nodes.count }

    /// All sections in the model, in insertion order.
    public var sections: [ModelSection] { sectionList }

    /// All node references in section order.
    public var allRefs: [NodeRef] {
        sectionList.flatMap(\.refs)
    }

    /// Returns the kind of the given node, or `nil` if not found.
    ///
    /// - Parameter ref: The node reference to look up.
    /// - Returns: The ``NodeKind`` of the node.
    public func kind(of ref: NodeRef) -> NodeKind? {
        nodes[ref]
    }

    /// Looks up a node by its label.
    ///
    /// - Parameter label: The label to search for.
    /// - Returns: The matching ``NodeRef``, or `nil` if no node has that label.
    public func node(named label: String) -> NodeRef? {
        nameIndex[label]
    }

    /// Returns the table registered with the given label.
    ///
    /// - Parameter label: The table label.
    /// - Returns: The ``TableRef``, or `nil` if no table has that label.
    public func table(named label: String) -> TableRef? {
        tableIndex[label]
    }

    /// All registered tables, keyed by label.
    public var allTables: [String: TableRef] {
        tableIndex
    }

    // MARK: - Adding Nodes

    /// Adds an input node with an editable numeric value.
    ///
    /// - Parameters:
    ///   - label: A human-readable name for this input.
    ///   - value: The default numeric value.
    ///   - section: The section to place this node in. Defaults to "Inputs".
    /// - Returns: The ``NodeRef`` identifying this node.
    @discardableResult
    public func addInput(
        label: String,
        value: Double,
        section: String = "Inputs"
    ) -> NodeRef {
        let ref = NodeRef(label: label)
        nodes[ref] = .input(value)
        nameIndex[label] = ref
        appendToSection(name: section, ref: ref)
        return ref
    }

    /// Adds an input node with an editable text value.
    ///
    /// - Parameters:
    ///   - label: A human-readable name for this input.
    ///   - value: The default text value.
    ///   - section: The section to place this node in. Defaults to "Inputs".
    /// - Returns: The ``NodeRef`` identifying this node.
    @discardableResult
    public func addTextInput(
        label: String,
        value: String,
        section: String = "Inputs"
    ) -> NodeRef {
        let ref = NodeRef(label: label)
        nodes[ref] = .textInput(value)
        nameIndex[label] = ref
        appendToSection(name: section, ref: ref)
        return ref
    }

    /// Adds a computed formula node.
    ///
    /// - Parameters:
    ///   - label: A human-readable name for this formula.
    ///   - formula: The ``NodeFormula`` expression.
    ///   - section: The section to place this node in. Defaults to "Calculations".
    /// - Returns: The ``NodeRef`` identifying this node.
    @discardableResult
    public func addFormula(
        label: String,
        formula: NodeFormula,
        section: String = "Calculations"
    ) -> NodeRef {
        let ref = NodeRef(label: label)
        nodes[ref] = .formula(formula)
        nameIndex[label] = ref
        appendToSection(name: section, ref: ref)
        return ref
    }

    /// Adds a highlighted output node.
    ///
    /// - Parameters:
    ///   - label: A human-readable name for this output.
    ///   - formula: The ``NodeFormula`` expression that computes the result.
    ///   - section: The section to place this node in. Defaults to "Results".
    /// - Returns: The ``NodeRef`` identifying this node.
    @discardableResult
    public func addOutput(
        label: String,
        formula: NodeFormula,
        section: String = "Results"
    ) -> NodeRef {
        let ref = NodeRef(label: label)
        nodes[ref] = .output(formula)
        nameIndex[label] = ref
        appendToSection(name: section, ref: ref)
        return ref
    }

    /// Adds a static text label node.
    ///
    /// - Parameters:
    ///   - text: The label text.
    ///   - section: The section to place this node in. Defaults to "Labels".
    /// - Returns: The ``NodeRef`` identifying this node.
    @discardableResult
    public func addLabel(
        _ text: String,
        section: String = "Labels"
    ) -> NodeRef {
        let ref = NodeRef(label: text)
        nodes[ref] = .label(text)
        nameIndex[text] = ref
        appendToSection(name: section, ref: ref)
        return ref
    }

    /// Registers a table of already-added nodes.
    ///
    /// The nodes in `rows` must already exist in the model.
    ///
    /// - Parameters:
    ///   - label: A display label for the table.
    ///   - columns: Column header names.
    ///   - rows: Node references organized as rows (outer) by columns (inner).
    /// - Returns: The ``TableRef`` for this table.
    @discardableResult
    public func registerTable(
        label: String,
        columns: [String],
        rows: [[NodeRef]]
    ) -> TableRef {
        let table = TableRef(label: label, columns: columns, rows: rows)
        tableIndex[label] = table
        return table
    }

    // MARK: - Private

    private func appendToSection(name: String, ref: NodeRef) {
        if let index = sectionList.firstIndex(where: { $0.name == name }) {
            sectionList[index].refs.append(ref)
        } else {
            sectionList.append(ModelSection(name: name, refs: [ref]))
        }
    }
}
