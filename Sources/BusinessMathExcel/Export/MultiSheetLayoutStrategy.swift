import SwiftXLSX

/// Lays out an ``ExcelModel`` across multiple worksheets.
///
/// By default, each section is assigned to its own sheet. Use ``groups``
/// to place multiple sections on the same sheet.
///
/// ## Usage
///
/// ```swift
/// // One section per sheet (default)
/// let strategy = MultiSheetLayoutStrategy()
///
/// // Group related sections
/// let grouped = MultiSheetLayoutStrategy(groups: [
///     SheetGroup(name: "Parameters", sections: ["Inputs", "Calculations"]),
///     SheetGroup(name: "Output", sections: ["Results"])
/// ])
/// ```
public struct MultiSheetLayoutStrategy: Sendable {

    /// The single-sheet strategy applied within each sheet.
    public let perSheetLayout: any LayoutStrategy

    /// Optional section-name-to-sheet-name overrides (used when no groups are specified).
    public let sheetNames: [String: String]

    /// Optional section grouping. When non-empty, sections listed in a group share a sheet.
    public let groups: [SheetGroup]

    /// Creates a multi-sheet layout strategy with section grouping.
    ///
    /// - Parameters:
    ///   - groups: Groups of sections to place on the same sheet. Sections not in any group get their own sheet.
    ///   - perSheetLayout: Strategy for positioning nodes within each sheet. Defaults to ``VerticalLayoutStrategy``.
    public init(
        groups: [SheetGroup],
        perSheetLayout: any LayoutStrategy = VerticalLayoutStrategy()
    ) {
        self.groups = groups
        self.perSheetLayout = perSheetLayout
        self.sheetNames = [:]
    }

    /// Creates a multi-sheet layout strategy with one section per sheet.
    ///
    /// - Parameters:
    ///   - perSheetLayout: Strategy for positioning nodes within each sheet. Defaults to ``VerticalLayoutStrategy``.
    ///   - sheetNames: Optional map from section name to custom sheet name.
    public init(
        perSheetLayout: any LayoutStrategy = VerticalLayoutStrategy(),
        sheetNames: [String: String] = [:]
    ) {
        self.perSheetLayout = perSheetLayout
        self.sheetNames = sheetNames
        self.groups = []
    }

    /// Assigns cell positions for all nodes across multiple sheets.
    ///
    /// - Parameter model: The model to lay out.
    /// - Returns: A ``MultiSheetAssignment`` with per-sheet assignments and global mapping.
    public func assign(_ model: ExcelModel) -> MultiSheetAssignment {
        let plan = buildSheetPlan(model: model)

        var sheets: [String: CellAssignment] = [:]
        var sheetOrder: [String] = []
        var globalMapping: [NodeRef: SheetCell] = [:]

        for (sheetName, sectionNames) in plan {
            let subModel = buildSubModel(
                sectionNames: sectionNames,
                from: model
            )

            let assignment = perSheetLayout.assign(subModel)
            sheets[sheetName] = assignment
            sheetOrder.append(sheetName)

            for sectionName in sectionNames {
                guard let section = model.sections.first(where: { $0.name == sectionName }) else {
                    continue
                }
                for ref in section.refs {
                    let subRef = subModel.node(named: ref.label)
                    if let subRef = subRef, let cell = assignment.mapping[subRef] {
                        globalMapping[ref] = SheetCell(sheetName: sheetName, cell: cell)
                    }
                }
            }
        }

        return MultiSheetAssignment(
            sheets: sheets,
            sheetOrder: sheetOrder,
            globalMapping: globalMapping
        )
    }

    // MARK: - Private

    private func buildSheetPlan(
        model: ExcelModel
    ) -> [(sheetName: String, sectionNames: [String])] {
        guard !groups.isEmpty else {
            return model.sections.map { section in
                let name = sheetNames[section.name] ?? section.name
                return (sheetName: name, sectionNames: [section.name])
            }
        }

        var plan: [(sheetName: String, sectionNames: [String])] = []
        var groupedSections: Set<String> = []

        for group in groups {
            let validSections = group.sections.filter { name in
                model.sections.contains { $0.name == name }
            }
            guard !validSections.isEmpty else { continue }
            plan.append((sheetName: group.name, sectionNames: validSections))
            for name in validSections {
                groupedSections.insert(name)
            }
        }

        for section in model.sections where !groupedSections.contains(section.name) {
            plan.append((sheetName: section.name, sectionNames: [section.name]))
        }

        return plan
    }

    private func buildSubModel(
        sectionNames: [String],
        from model: ExcelModel
    ) -> ExcelModel {
        let subModel = ExcelModel()

        for sectionName in sectionNames {
            guard let section = model.sections.first(where: { $0.name == sectionName }) else {
                continue
            }

            for ref in section.refs {
                guard let kind = model.kind(of: ref) else { continue }
                switch kind {
                case .input(let value):
                    subModel.addInput(label: ref.label, value: value, section: sectionName)
                case .textInput(let value):
                    subModel.addTextInput(label: ref.label, value: value, section: sectionName)
                case .formula(let formula):
                    subModel.addFormula(label: ref.label, formula: formula, section: sectionName)
                case .output(let formula):
                    subModel.addOutput(label: ref.label, formula: formula, section: sectionName)
                case .label(let text):
                    subModel.addLabel(text, section: sectionName)
                }
            }

            if let table = model.table(named: sectionName) {
                let subRefs = subModel.sections
                    .first { $0.name == sectionName }?
                    .refs ?? []
                var tableRows: [[NodeRef]] = []
                var refIndex = 0
                for originalRow in table.rows {
                    var newRow: [NodeRef] = []
                    for _ in originalRow {
                        guard refIndex < subRefs.count else { break }
                        newRow.append(subRefs[refIndex])
                        refIndex += 1
                    }
                    tableRows.append(newRow)
                }
                subModel.registerTable(
                    label: table.label,
                    columns: table.columns,
                    rows: tableRows
                )
            }
        }

        return subModel
    }
}
