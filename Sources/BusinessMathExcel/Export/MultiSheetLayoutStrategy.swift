import SwiftXLSX

/// Lays out an ``ExcelModel`` with each section on its own worksheet.
///
/// Each section is assigned to a separate sheet, and nodes within each sheet
/// are positioned using the ``perSheetLayout`` strategy. The resulting
/// ``MultiSheetAssignment`` contains per-sheet ``CellAssignment`` values
/// and a global mapping for cross-sheet formula resolution.
///
/// ## Usage
///
/// ```swift
/// let strategy = MultiSheetLayoutStrategy(
///     perSheetLayout: CompactLayoutStrategy()
/// )
/// let assignment = strategy.assign(model)
/// // assignment.sheetOrder == ["Inputs", "Calculations", "Results"]
/// ```
public struct MultiSheetLayoutStrategy: Sendable {

    /// The single-sheet strategy applied within each sheet.
    public let perSheetLayout: any LayoutStrategy

    /// Optional section-name-to-sheet-name overrides.
    public let sheetNames: [String: String]

    /// Creates a multi-sheet layout strategy.
    ///
    /// - Parameters:
    ///   - perSheetLayout: Strategy for positioning nodes within each sheet. Defaults to ``VerticalLayoutStrategy``.
    ///   - sheetNames: Optional map from section name to custom sheet name. Sections not in the map use their section name.
    public init(
        perSheetLayout: any LayoutStrategy = VerticalLayoutStrategy(),
        sheetNames: [String: String] = [:]
    ) {
        self.perSheetLayout = perSheetLayout
        self.sheetNames = sheetNames
    }

    /// Assigns cell positions for all nodes, one sheet per section.
    ///
    /// - Parameter model: The model to lay out.
    /// - Returns: A ``MultiSheetAssignment`` with per-sheet assignments and global mapping.
    public func assign(_ model: ExcelModel) -> MultiSheetAssignment {
        var sheets: [String: CellAssignment] = [:]
        var sheetOrder: [String] = []
        var globalMapping: [NodeRef: SheetCell] = [:]

        for section in model.sections {
            let sheetName = sheetNames[section.name] ?? section.name

            let sectionModel = ExcelModel()
            for ref in section.refs {
                guard let kind = model.kind(of: ref) else { continue }
                switch kind {
                case .input(let value):
                    sectionModel.addInput(label: ref.label, value: value, section: section.name)
                case .textInput(let value):
                    sectionModel.addTextInput(label: ref.label, value: value, section: section.name)
                case .formula(let formula):
                    sectionModel.addFormula(label: ref.label, formula: formula, section: section.name)
                case .output(let formula):
                    sectionModel.addOutput(label: ref.label, formula: formula, section: section.name)
                case .label(let text):
                    sectionModel.addLabel(text, section: section.name)
                }
            }

            if let table = model.table(named: section.name) {
                let sectionRefs = sectionModel.allRefs
                var tableRows: [[NodeRef]] = []
                var refIndex = 0
                for originalRow in table.rows {
                    var newRow: [NodeRef] = []
                    for _ in originalRow {
                        guard refIndex < sectionRefs.count else { break }
                        newRow.append(sectionRefs[refIndex])
                        refIndex += 1
                    }
                    tableRows.append(newRow)
                }
                sectionModel.registerTable(
                    label: table.label,
                    columns: table.columns,
                    rows: tableRows
                )
            }

            let assignment = perSheetLayout.assign(sectionModel)
            sheets[sheetName] = assignment
            sheetOrder.append(sheetName)

            for ref in section.refs {
                let sectionRef = sectionModel.node(named: ref.label)
                if let sectionRef = sectionRef, let cell = assignment.mapping[sectionRef] {
                    globalMapping[ref] = SheetCell(sheetName: sheetName, cell: cell)
                }
            }
        }

        return MultiSheetAssignment(
            sheets: sheets,
            sheetOrder: sheetOrder,
            globalMapping: globalMapping
        )
    }
}
