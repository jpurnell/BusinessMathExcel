# Design Proposal: CompactLayoutStrategy and MultiSheetLayoutStrategy

**Date:** 2026-06-05
**Status:** Proposed
**Master Plan Reference:** Future Work — CompactLayoutStrategy, Multi-sheet strategies

---

## 1. Objective

Add two new layout strategies to BusinessMathExcel:

1. **CompactLayoutStrategy** — Vertical layout with no blank separator rows between sections, producing tighter, denser worksheets.
2. **MultiSheetLayoutStrategy** — Each section placed on its own worksheet, with cross-sheet formula references for nodes that depend on values in other sections.

## 2. Motivation

**Current situation:** All existing strategies render to a single worksheet. `VerticalLayoutStrategy` adds a blank separator row between sections, wasting vertical space. There is no way to split a model across worksheets.

**Workaround (compact):** Users manually adjust `VerticalLayoutStrategy` output or build custom assignment dictionaries. There is no built-in compact option.

**Workaround (multi-sheet):** Users export sections individually to separate workbooks, losing cross-section formula references entirely. No live cross-sheet formulas are possible.

**Drawback:** Dense models with many sections waste rows. Complex models that would benefit from worksheet-per-topic organization (e.g., Inputs on one sheet, Schedule on another, Results on a third) cannot be represented.

## 3. Proposed Architecture

### Part A: CompactLayoutStrategy

**New Files:**
- `Sources/BusinessMathExcel/Export/CompactLayoutStrategy.swift`

**Modified Files:** None. This is a standalone `LayoutStrategy` conformance.

**Module Placement:** `Export/` (same as other strategies)

**Design:** Identical to `VerticalLayoutStrategy` except: no `row += 1` separator after each section. Sections flow directly from one to the next with only the section header as the visual break. Table-aware: detects registered `TableRef` and renders as grid with column headers, same as Horizontal and Dashboard strategies.

### Part B: MultiSheetLayoutStrategy

**New Files:**
- `Sources/BusinessMathExcel/Export/MultiSheetLayoutStrategy.swift`
- `Sources/BusinessMathExcel/Export/MultiSheetAssignment.swift`
- `Sources/BusinessMathExcel/Export/MultiSheetExporter.swift`

**Modified Files:**
- `Sources/BusinessMathExcel/Model/NodeFormula.swift` — add `sheetRef(String, NodeRef)` case for cross-sheet node references

**Module Placement:** `Export/` and `Model/`

**Design:** Multi-sheet export uses a parallel pipeline that does not modify the existing `LayoutStrategy` protocol. Instead:

1. A new `MultiSheetLayoutStrategy` struct maps each section to a sheet name and computes per-sheet `CellAssignment` using a configurable per-sheet `LayoutStrategy`.
2. A new `MultiSheetAssignment` type holds the mapping from sheet name to `CellAssignment`, plus a global `[NodeRef: (sheetName: String, cell: CellRef)]` for cross-sheet resolution.
3. A new `MultiSheetExporter` writes each sheet using the per-sheet assignment, resolving cross-sheet formulas to `FormulaAST.sheetRef(SheetReference)`.

**Why not extend `LayoutStrategy`?** The existing protocol returns a single `CellAssignment` — a single-sheet concept. Adding multi-sheet semantics to `CellAssignment` (e.g., an optional `sheetName` per mapping entry) would break the mental model and require every existing strategy consumer to handle the new dimension. A parallel type is cleaner.

**Why `MultiSheetExporter` instead of extending `ModelExporter`?** `ModelExporter.export()` has a clear single-sheet contract (one `sheetName` parameter, one `Worksheet`). Adding multi-sheet logic there would create a confusing branching API. A dedicated exporter for multi-sheet output keeps each exporter focused.

## 4. API Surface

### CompactLayoutStrategy

```swift
public struct CompactLayoutStrategy: LayoutStrategy, Sendable {
    public let labelColumn: Int     // default 3
    public let valueColumn: Int     // default 4

    public init(labelColumn: Int = 3, valueColumn: Int = 4)
    public func assign(_ model: ExcelModel) -> CellAssignment
}
```

### MultiSheetAssignment

```swift
public struct MultiSheetAssignment: Sendable {
    /// Per-sheet cell assignments, keyed by sheet name.
    public let sheets: [String: CellAssignment]

    /// The ordered list of sheet names (insertion order).
    public let sheetOrder: [String]

    /// Global node-to-sheet+cell mapping for cross-sheet formula resolution.
    public let globalMapping: [NodeRef: SheetCell]
}

public struct SheetCell: Sendable, Equatable, Hashable {
    public let sheetName: String
    public let cell: CellRef
}
```

### MultiSheetLayoutStrategy

```swift
public struct MultiSheetLayoutStrategy: Sendable {
    /// The single-sheet strategy applied within each sheet.
    public let perSheetLayout: any LayoutStrategy

    /// Optional custom sheet name mapping. Defaults to section name.
    public let sheetNames: [String: String]

    public init(
        perSheetLayout: any LayoutStrategy = VerticalLayoutStrategy(),
        sheetNames: [String: String] = [:]
    )

    public func assign(_ model: ExcelModel) -> MultiSheetAssignment
}
```

### MultiSheetExporter

```swift
public enum MultiSheetExporter {
    public static func export(
        _ model: ExcelModel,
        title: String = "Model",
        layout: MultiSheetLayoutStrategy = .init(),
        design: DesignBundle = .default
    ) throws -> Workbook
}
```

### NodeFormula extension

```swift
// New case added to NodeFormula:
case sheetRef(String, NodeRef)  // sheet name + node reference

// New resolve overload:
public func resolve(using mapping: [NodeRef: CellRef],
                    sheetMapping: [NodeRef: SheetCell]) throws -> FormulaAST
```

The existing `resolve(using:)` method remains unchanged. The new overload is used only by `MultiSheetExporter`. When resolving `.sheetRef(sheetName, ref)`, it produces `FormulaAST.sheetRef(SheetReference(sheet: sheetName, cell: cellRef))`.

For formulas that reference nodes on other sheets via plain `.ref(nodeRef)`, the exporter checks: if the referenced node is on the current sheet, resolve normally. If it is on a different sheet, resolve via `sheetMapping` to produce a `FormulaAST.sheetRef`.

## 5. MCP Schema

**CompactLayoutStrategy:**
```json
{
  "layout": "compact",
  "labelColumn": 3,
  "valueColumn": 4
}
```

**MultiSheetLayoutStrategy:**
```json
{
  "layout": "multiSheet",
  "perSheetLayout": "vertical",
  "sheetNames": {
    "Inputs": "Loan Parameters",
    "Schedule": "Amortization Schedule"
  }
}
```

**Parameter Types:**
- layout (string): "compact" or "multiSheet"
- labelColumn (integer): 1-based column index for labels
- valueColumn (integer): 1-based column index for values
- perSheetLayout (string): Name of per-sheet strategy ("vertical", "compact", "horizontal", "dashboard")
- sheetNames (object): Optional section-name-to-sheet-name override map

## 6. Constraints & Compliance

**Concurrency:** All new types are Sendable value types (structs/enums).
**Safety:** No force unwraps, guard-based validation, bounded iteration.
**Generics:** Not required — these operate on concrete ExcelModel types.
**Backward Compatibility:** Existing `LayoutStrategy` protocol, `CellAssignment`, and `ModelExporter` are unchanged. `NodeFormula` gains a new case — existing `switch` exhaustiveness will require adding `case .sheetRef` handlers (source-breaking for external consumers who switch on `NodeFormula`).

## 7. Source & API Compatibility

**CompactLayoutStrategy:** No breaking changes — entirely new type.

**MultiSheetLayoutStrategy:** No changes to existing types except:
- `NodeFormula` gains `.sheetRef(String, NodeRef)` case. This is source-breaking for any external code that has an exhaustive `switch` on `NodeFormula`. However, since `NodeFormula` is an `indirect enum` in this package and external consumers are unlikely to exhaustively switch on it, the risk is low.

**Mitigation:** The `.sheetRef` case is optional — models that don't use multi-sheet export never encounter it. The new `resolve(using:sheetMapping:)` overload does not affect the existing `resolve(using:)`.

**Incremental adoption:** CompactLayoutStrategy can be used immediately with existing `ModelExporter`. MultiSheetLayoutStrategy requires `MultiSheetExporter` — consumers opt in by switching their export call.

## 8. Backend Abstraction

Not applicable — layout computation is O(n) in node count with no compute-intensive operations.

## 9. Dependencies

**Internal Dependencies:**
- `ExcelModel`, `NodeRef`, `NodeFormula`, `CellAssignment` (Model/)
- `LayoutStrategy` protocol (Export/)
- `ModelExporter` patterns (Export/) — referenced but not modified
- SwiftXLSX: `FormulaAST.sheetRef`, `SheetReference`, `Workbook.addSheet(name:)`

**External Dependencies:** None.

## 10. Test Strategy

### CompactLayoutStrategy Tests (~14 tests)
- Empty model → empty assignment
- Single section → labels/values at correct positions, no separator
- Multi-section → sections flow without blank rows between them
- Section headers → each section has header at correct row (no gaps)
- Custom label/value columns → positions shift correctly
- All refs assigned → every node appears in mapping
- No cell collisions → all cells unique
- Comparison with VerticalLayoutStrategy → compact produces fewer rows
- Table-aware: section with registered table renders as grid
- Table-aware: column headers populated in `tableColumnHeaders`
- Table-aware: table body nodes omitted from `labelMapping`
- Table-aware: mixed table and non-table sections handled correctly
- Integration: CompactLayoutStrategy + ModelExporter → valid workbook
- Integration: CompactLayoutStrategy + AmortizationModelBuilder (table) → correct output

**Reference Truth:** Row positions computed by hand. Compact should produce `lastRow = headerRows + nodeRows + sectionCount` (one header per section, no blanks).

**Validation Trace:**
- Model with 2 sections (3 nodes, 2 nodes): Vertical uses rows 3-10 (header, 3 nodes, blank, header, 2 nodes, blank). Compact uses rows 3-9 (header, 3 nodes, header, 2 nodes) → `lastRow = 10` for compact vs `11` for vertical.

### MultiSheetAssignment Tests (~5 tests)
- sheets dictionary populated per section
- sheetOrder preserves insertion order
- globalMapping contains all nodes with correct sheet names
- SheetCell equality and hashing

### MultiSheetLayoutStrategy Tests (~10 tests)
- Empty model → empty assignment
- Single section → one sheet with correct assignment
- Multi-section → one sheet per section
- Custom sheet names → override map applied
- Per-sheet layout respected → nodes positioned per inner strategy
- Global mapping → all nodes present with correct sheet+cell
- Section with table → table-aware per-sheet layout preserved
- Integration: MultiSheetLayoutStrategy + AmortizationModelBuilder

### MultiSheetExporter Tests (~8 tests)
- Single-section model → one sheet in workbook
- Multi-section model → N sheets in workbook
- Cross-sheet formula → resolves to `SheetReference` in output
- Same-sheet formula → resolves to normal `CellRef`
- Title written on each sheet
- Section headers written per sheet
- Table headers written when present
- Integration: full round-trip with DCFModelBuilder

### NodeFormula.sheetRef Tests (~4 tests)
- `.sheetRef` case resolves to `FormulaAST.sheetRef`
- Dangling reference throws `ResolutionError`
- Existing resolve method ignores `.sheetRef` (throws dangling)
- New overload resolves cross-sheet correctly

**Estimated total: ~41 new tests**

## 11. Architecture Decision Review

**ADR Check:**
- [x] Reviewed `architecture_decisions.md` for related decisions
- [ ] Does this supersede an existing ADR? No
- [ ] Does this amend an existing ADR? No
- [x] New ADR required? Yes

**New ADR Draft:**
- Title: Multi-sheet export uses parallel pipeline, not protocol extension
- Category: architecture
- Key decision: Multi-sheet layout gets its own strategy type (`MultiSheetLayoutStrategy`) and exporter (`MultiSheetExporter`) rather than extending the existing `LayoutStrategy` protocol and `ModelExporter`, because the single-sheet contract is fundamental to the current abstraction.

## 12. Adversarial Review

**Strongest case for a different approach:**
A reviewer would argue that `MultiSheetLayoutStrategy` should conform to `LayoutStrategy` and return a `CellAssignment` that contains sheet-name metadata, keeping a single export entry point. This would mean any code that works with `LayoutStrategy` automatically handles multi-sheet output.

Why it might be better: one protocol, one exporter, one mental model. Consumers don't need to know whether their layout is single-sheet or multi-sheet — they call `ModelExporter.export()` with any strategy.

**Where this design is most likely wrong:**
The assumption that `NodeFormula.sheetRef` is needed as a distinct case. In practice, formulas reference nodes by `NodeRef` — the exporter knows which sheet each node lives on and could auto-resolve cross-sheet references at export time without the formula itself knowing about sheets. Adding `.sheetRef` to `NodeFormula` pushes sheet awareness into the model layer, which currently has no concept of sheets.

**What an experienced critic would say:**
"You're adding a `.sheetRef` case to a core enum that was intentionally sheet-agnostic, just so the exporter can be simpler — push the cross-sheet resolution entirely into the exporter instead."

We should seriously consider this: the exporter already has the global mapping and knows which sheet each node is on. During `resolve(using:)`, if a `.ref(nodeRef)` maps to a cell on a different sheet, the exporter can wrap the result in `FormulaAST.sheetRef(SheetReference(sheet:cell:))` post-resolution. This would eliminate the need for `.sheetRef` on `NodeFormula` entirely.

**Revised approach based on this review:** Drop `NodeFormula.sheetRef`. Instead, `MultiSheetExporter` performs two-pass resolution:
1. Resolve formula using the per-sheet mapping (which includes all nodes from all sheets with their cell positions)
2. Walk the resolved `FormulaAST`, and for any `.cellRef` that maps to a node on a different sheet, replace it with `.sheetRef(SheetReference(sheet:cell:))`

This keeps `NodeFormula` sheet-agnostic and confines cross-sheet awareness to the exporter layer.

## 13. Alternatives Considered

**Alternative 1: Extend LayoutStrategy protocol with associated type**
```swift
protocol LayoutStrategy {
    associatedtype Assignment
    func assign(_ model: ExcelModel) -> Assignment
}
```
- Advantage: One protocol for both single and multi-sheet
- Disadvantage: Makes `LayoutStrategy` generic, breaks `any LayoutStrategy` usage in `ModelExporter`, and requires type-erasing wrappers
- Why rejected: Backward compatibility; the current `any LayoutStrategy` parameter is clean

**Alternative 2: Add `sheetName` to CellAssignment entries**
```swift
struct CellAssignment {
    // existing fields...
    let sheetMapping: [NodeRef: String]  // which sheet each node goes to
}
```
- Advantage: Single type for both single and multi-sheet
- Disadvantage: Every consumer must handle the possibility of multiple sheets. Single-sheet strategies must still populate or ignore the field. `ModelExporter` becomes more complex.
- Why rejected: Violates single-responsibility; CellAssignment should describe one sheet's layout

**Alternative 3: CompactLayoutStrategy as VerticalLayoutStrategy init parameter**
```swift
VerticalLayoutStrategy(compact: true)
```
- Advantage: No new type; less API surface
- Disadvantage: Boolean parameters obscure intent; as more options accumulate, `VerticalLayoutStrategy` becomes a kitchen-sink
- Why rejected: Separate types are clearer and follow the pattern established by `HorizontalLayoutStrategy` and `DashboardLayoutStrategy`

## 14. Future Directions

- **VerticalLayoutStrategy table awareness** — could add table detection to the original vertical strategy via opt-in init parameter
- **SectionGrouping for multi-sheet** — group related sections onto the same sheet rather than strict 1:1
- **Cross-sheet named ranges** — use Excel named ranges for cross-sheet references instead of raw cell refs
- **Sheet ordering control** — custom sheet tab order in the workbook
- **Summary sheet** — auto-generated sheet that references key outputs from other sheets

## 15. Open Questions

1. **Should CompactLayoutStrategy support table-aware rendering?** Yes — decided. All new strategies should be table-aware for consistency. CompactLayoutStrategy will detect registered `TableRef` and render as grid with column headers, same as Horizontal and Dashboard strategies. This also means `VerticalLayoutStrategy` is now the only non-table-aware strategy.

2. **Should MultiSheetExporter auto-detect cross-sheet references, or require explicit configuration?** The proposed design auto-detects: if a formula's `.ref(nodeRef)` resolves to a cell on a different sheet, the exporter wraps it in `SheetReference`. This seems sufficient — the model builder doesn't need to think about sheets.

3. **Should sections with no formulas referencing other sections still get their own sheet?** Yes — the strategy is "one section, one sheet" by default. A future `SectionGrouping` feature could combine sections.

## 16. Documentation Strategy

**Documentation Type:** Narrative Article Required

**Complexity Threshold Check:**
- Does it combine 3+ APIs? Yes (MultiSheetLayoutStrategy + MultiSheetAssignment + MultiSheetExporter + SheetCell)
- Does explanation require 50+ lines? Yes
- Does it need theory/background context? Yes (cross-sheet formula resolution)

**Article Name:** LayoutStrategyGuide.md (extends existing concept from v0.4.0)

---

## Implementation Phases

### Phase A: CompactLayoutStrategy (straightforward)
1. RED: Write ~10 failing tests
2. GREEN: Implement CompactLayoutStrategy (simplified VerticalLayoutStrategy)
3. REFACTOR + DOCUMENT + VERIFY

### Phase B: MultiSheetAssignment + SheetCell types
1. RED: Write ~5 failing tests for data types
2. GREEN: Implement SheetCell, MultiSheetAssignment
3. REFACTOR + DOCUMENT + VERIFY

### Phase C: MultiSheetLayoutStrategy
1. RED: Write ~10 failing tests
2. GREEN: Implement strategy (delegates to per-sheet layout, builds global mapping)
3. REFACTOR + DOCUMENT + VERIFY

### Phase D: MultiSheetExporter
1. RED: Write ~8 failing tests
2. GREEN: Implement exporter with cross-sheet formula resolution
3. REFACTOR + DOCUMENT + VERIFY

### Phase E: Integration + Quality Gate
1. Full integration tests with builders
2. Quality gate pass
3. CHANGELOG, session summary

**Estimated total: ~41 tests across 4-5 test files**
