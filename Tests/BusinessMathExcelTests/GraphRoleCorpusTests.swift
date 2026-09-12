import XCTest
@testable import BusinessMathExcel
import SwiftXLSX

/// Does the topology agree with how a modeller labelled their own sheet?
///
/// ``GraphPartition`` sorts cells by their edges alone — no labels, no formats, no
/// position. That is what makes it general, and also what makes it worth checking
/// against a sheet where a person wrote the answer down.
///
/// Kelly's Roast Beef is that sheet: a bond cash-matching linear program from a
/// Decision Science course, structured the way the course teaches — `Parameters`,
/// `Decision Variables`, `Objective Function`, `Calculation` — with those words in
/// column A. Header detection finds no timeline on it at all, so it is exactly the
/// kind of sheet recognition cannot read and the graph can.
///
/// Reported, not gated. The point is to see where topology and a human's labels
/// agree and where they part company; an assertion tuned to one workbook would be
/// the fitting this whole direction exists to get away from.
final class GraphRoleCorpusTests: XCTestCase {

    private func workbook(named fragment: String) throws -> (name: String, book: Workbook) {
        guard let configured = ProcessInfo.processInfo.environment["BUSINESSMATHEXCEL_CORPUS"],
              !configured.isEmpty
        else {
            throw XCTSkip("Set BUSINESSMATHEXCEL_CORPUS. The workbooks are private.")
        }

        for root in configured.split(separator: ":").map(String.init) {
            guard let walk = FileManager.default.enumerator(atPath: root) else { continue }
            for case let entry as String in walk
            where entry.lowercased().contains(fragment.lowercased())
                && entry.lowercased().hasSuffix(".xlsx") && !entry.contains("~$") {
                let path = root + "/" + entry
                guard let book = try? Workbook(contentsOf: URL(fileURLWithPath: path)) else {
                    continue
                }
                return ((entry as NSString).lastPathComponent, book)
            }
        }
        throw XCTSkip("No workbook matching '\(fragment)' under the configured roots.")
    }

    /// A row number in a three-wide column, so the rows line up when read.
    private func rightAligned(_ row: Int) -> String {
        let digits = String(row)
        guard digits.count < 3 else { return digits }
        return String(repeating: " ", count: 3 - digits.count) + digits
    }

    /// The words in a cell, whichever way the importer classified them.
    ///
    /// Read through ``SheetGrid`` rather than the worksheet, because a worksheet's
    /// cell store is SwiftXLSX's own and the import layer is how this project is
    /// meant to reach it.
    private func text(_ kind: NodeKind?) -> String? {
        let string: String
        switch kind {
        case .textInput(let value): string = value
        case .label(let value): string = value
        default: return nil
        }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The partition beside the sheet's own headings, sheet by sheet.
    func testTheGraphsRolesAgainstAHumansLabels() throws {
        let (name, book) = try workbook(named: "Kelly")

        // Three scopes, because what counts as a cell decides what the partition
        // can mean. A sheet holds blank-but-formatted cells in their hundreds; if
        // they enter the graph they land in `unreachable` and drown the captions
        // and stranded figures that bucket exists to surface.
        let scopes: [(String, ((CellValue) -> Bool)?)] = [
            ("every cell", nil),
            ("not blank", { if case .blank = $0.resolved { return false }; return true }),
            ("quantities", { value in
                if value.isFormula { return true }
                if case .number = value.resolved { return true }
                return false
            }),
        ]

        for sheet in book.sheets {
            guard !GraphPartition(sheet: sheet).roles.isEmpty else { continue }
            for (scopeName, filter) in scopes {
                let scoped = GraphPartition(sheet: sheet, including: filter)
                let counts = scoped.counts
                print("KELLY  scope \"\(scopeName)\": \(scoped.roles.count) cells — "
                    + "parameter \(counts[.parameter] ?? 0), "
                    + "calculation \(counts[.calculation] ?? 0), "
                    + "objective \(counts[.objective] ?? 0), "
                    + "unreachable \(counts[.unreachable] ?? 0)")
            }

            let partition = GraphPartition(sheet: sheet, including: scopes[1].1)

            let counts = partition.counts
            print("KELLY  \(name) — sheet \"\(sheet.name)\": "
                + "parameter \(counts[.parameter] ?? 0), "
                + "calculation \(counts[.calculation] ?? 0), "
                + "objective \(counts[.objective] ?? 0), "
                + "unreachable \(counts[.unreachable] ?? 0)")

            // Column A, as the modeller wrote it, with the role of everything on
            // the same row. Where the two agree, the labels are describing the
            // topology; where they do not, that is the finding.
            let grid = SheetGrid.build(from: ModelImporter.importSheet(sheet))
            var labelRows: [(row: Int, label: String)] = []
            for (ref, kind) in grid.cells where ref.column == 1 {
                if let label = text(kind) { labelRows.append((ref.row, label)) }
            }

            let labelByRow = Dictionary(labelRows.map { ($0.row, $0.label) }) { first, _ in first }
            let rows = Set(partition.roles.keys.map(\.cell.row)).sorted()

            for row in rows {
                let onThisRow = partition.roles
                    .filter { $0.key.cell.row == row && $0.key.cell.column > 1 }
                    .map(\.value)
                let tally = Dictionary(grouping: onThisRow, by: { $0 })
                    .mapValues(\.count)
                    .sorted { $0.key.rawValue < $1.key.rawValue }
                    .map { "\($0.key.rawValue) \($0.value)" }
                    .joined(separator: ", ")
                let label = labelByRow[row].map { "\"\($0)\"" } ?? ""
                print("KELLY    row \(rightAligned(row))  \(tally.isEmpty ? "—" : tally)"
                    + (label.isEmpty ? "" : "   \(label)"))
            }
        }

        // Does the file state its decisions? Excel records Solver's configuration in
        // defined names — `solver_adj` for the adjustable cells, `solver_opt` for
        // the objective. Where they survive a save, a decision variable is read
        // rather than inferred, which is the only way to tell one from a parameter.
        let names = book.namedRanges.all
        print("KELLY  defined names: \(names.count)")
        for named in names.sorted(by: { $0.name < $1.name }) {
            print("KELLY    \(named.name) → \(named.reference)")
        }

        XCTAssertFalse(book.sheets.isEmpty)
    }
}
