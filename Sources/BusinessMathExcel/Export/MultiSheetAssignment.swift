import SwiftXLSX

/// A named group of sections that share a single worksheet.
///
/// Use with ``MultiSheetLayoutStrategy`` to place multiple sections
/// on the same sheet instead of the default one-section-per-sheet behavior.
public struct SheetGroup: Sendable {

    /// The worksheet name for this group.
    public let name: String

    /// The section names to include on this sheet, in order.
    public let sections: [String]

    /// Creates a sheet group.
    ///
    /// - Parameters:
    ///   - name: The worksheet name.
    ///   - sections: Section names to include on this sheet.
    public init(name: String, sections: [String]) {
        self.name = name
        self.sections = sections
    }
}

/// A cell position qualified by worksheet name, for cross-sheet formula resolution.
public struct SheetCell: Sendable, Equatable, Hashable {

    /// The name of the worksheet containing this cell.
    public let sheetName: String

    /// The cell position within the worksheet.
    public let cell: CellRef

    /// Creates a sheet-qualified cell reference.
    ///
    /// - Parameters:
    ///   - sheetName: The worksheet name.
    ///   - cell: The cell position.
    public init(sheetName: String, cell: CellRef) {
        self.sheetName = sheetName
        self.cell = cell
    }
}

/// The result of laying out an ``ExcelModel`` across multiple worksheets.
///
/// Each section in the model maps to its own worksheet. The ``globalMapping``
/// provides a unified lookup for cross-sheet formula resolution.
public struct MultiSheetAssignment: Sendable {

    /// Per-sheet cell assignments, keyed by sheet name.
    public let sheets: [String: CellAssignment]

    /// The ordered list of sheet names, matching model section order.
    public let sheetOrder: [String]

    /// Maps every node to its sheet-qualified cell position.
    public let globalMapping: [NodeRef: SheetCell]

    /// Creates a multi-sheet assignment.
    ///
    /// - Parameters:
    ///   - sheets: Per-sheet cell assignments.
    ///   - sheetOrder: Sheet names in order.
    ///   - globalMapping: Node-to-sheet+cell mapping.
    public init(
        sheets: [String: CellAssignment],
        sheetOrder: [String],
        globalMapping: [NodeRef: SheetCell]
    ) {
        self.sheets = sheets
        self.sheetOrder = sheetOrder
        self.globalMapping = globalMapping
    }
}
