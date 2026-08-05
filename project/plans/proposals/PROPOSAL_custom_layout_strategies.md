# Design Proposal: Custom Layout Strategies

**Date:** 2026-06-04
**Status:** PROPOSED
**Master Plan Reference:** v0.3.0 Future Work — Custom LayoutStrategy implementations

---

## 1. Objective

Add three new `LayoutStrategy` implementations and extend `CellAssignment` with table-awareness so that ExcelModel workbooks can be exported in layouts beyond the current vertical stack.

---

## 2. Motivation

**Current situation:** `VerticalLayoutStrategy` is the only concrete strategy. Every exported workbook gets the same layout: labels in column C, values in column D, all sections stacked top-to-bottom. Additionally, `TableRef` is registered by builders (e.g., `AmortizationModelBuilder` registers a "Schedule" table) but completely ignored during layout — table data appears as a flat list of individual nodes instead of a structured grid with column headers.

**Pain points:**
- Models with many small sections waste vertical space (e.g., 5 sections with 3 nodes each produce a 30+ row spreadsheet that could fit in a compact 2-column grid)
- Side-by-side comparison of Inputs vs Results is impossible without manual rearrangement
- Amortization schedules render as flat lists ("Period 1", "BegBal 1", "Payment 1", ...) instead of proper tabular grids with column headers

**Workaround:** Consumers must manually rearrange cells in Excel after export, defeating the purpose of automated generation.

---

## 3. Proposed Architecture

### New Files

| File | Purpose |
|------|---------|
| `Sources/BusinessMathExcel/Export/HorizontalLayoutStrategy.swift` | Sections side-by-side |
| `Sources/BusinessMathExcel/Export/DashboardLayoutStrategy.swift` | N-column grid of sections |

### Modified Files

| File | Change |
|------|--------|
| `Sources/BusinessMathExcel/Export/LayoutStrategy.swift` | Add `tableColumnHeaders` to `CellAssignment` |
| `Sources/BusinessMathExcel/Model/ExcelModel.swift` | Add `public var allTables: [String: TableRef]` |
| `Sources/BusinessMathExcel/Export/ModelExporter.swift` | Write table column headers when present |

### Unchanged

All builders, `MonteCarloExtension`, `NodeRef`, `NodeFormula`, `ResolutionError`, and `VerticalLayoutStrategy` remain unchanged. The existing `VerticalLayoutStrategy` continues to produce the same output as before (no table awareness by default — this preserves backward compatibility).

---

## 4. API Surface

### CellAssignment (extended)

```swift
public struct CellAssignment: Sendable {
    public let mapping: [NodeRef: CellRef]
    public let labelMapping: [NodeRef: CellRef]
    public let sectionRows: [String: Int]
    public let lastRow: Int
    /// Column header positions for registered tables, keyed by table label.
    /// Layout strategies that support table-aware rendering populate this;
    /// strategies that don't leave it empty.
    public let tableColumnHeaders: [String: [CellRef]]

    public init(
        mapping: [NodeRef: CellRef],
        labelMapping: [NodeRef: CellRef],
        sectionRows: [String: Int],
        lastRow: Int,
        tableColumnHeaders: [String: [CellRef]] = [:]
    )
}
```

**Key behavior:** When a strategy renders a section as a table grid, it:
- Places column headers in `tableColumnHeaders` (text from `TableRef.columns`)
- Maps node values to grid positions in `mapping` (one cell per table cell)
- Omits table-body nodes from `labelMapping` (no per-node labels in a grid — the column header replaces them)
- Still writes non-table sections normally with both `mapping` and `labelMapping`

### ExcelModel (new accessor)

```swift
extension ExcelModel {
    /// All registered tables, keyed by label.
    public var allTables: [String: TableRef] { tableIndex }
}
```

### HorizontalLayoutStrategy

```swift
/// Lays out an ``ExcelModel`` with sections arranged side-by-side.
///
/// Each section occupies a column pair (label + value). Non-table sections
/// stack their nodes vertically within the column pair. Table sections
/// are rendered as grids spanning multiple columns.
public struct HorizontalLayoutStrategy: LayoutStrategy, Sendable {

    /// The 1-based column for the first section.
    public let startColumn: Int

    /// Blank columns between adjacent sections.
    public let sectionGap: Int

    /// The 1-based row where section content begins (after title).
    public let startRow: Int

    public init(startColumn: Int = 3, sectionGap: Int = 1, startRow: Int = 3)
    public func assign(_ model: ExcelModel) -> CellAssignment
}
```

**Layout algorithm:**
```
Row 1: Title
Row 2: Blank separator
Row 3+:

  Col C  Col D    Col F  Col G    Col I  Col J
  ───────────    ───────────    ───────────
  Inputs         Calcs          Results
  ───────────    ───────────    ───────────
  Principal  ▪   Monthly Rt ▪   Total Pmt ▪
  Rate       ▪   Payment    ▪   Total Int ▪
  Term       ▪
```

Each section gets columns `[col, col+1]` for labels and values. Next section starts at `col + 2 + sectionGap`. Table-registered sections span `TableRef.columns.count` value columns instead of 1.

### DashboardLayoutStrategy

```swift
/// Lays out an ``ExcelModel`` in a grid of sections.
///
/// Sections are arranged left-to-right in rows of ``columnCount`` sections,
/// wrapping to new row-bands when the current band is full.
public struct DashboardLayoutStrategy: LayoutStrategy, Sendable {

    /// Number of sections per row-band.
    public let columnCount: Int

    /// The 1-based column where the grid starts.
    public let startColumn: Int

    /// Blank columns between sections in the same row-band.
    public let sectionGap: Int

    /// Blank rows between row-bands.
    public let bandGap: Int

    public init(columnCount: Int = 2, startColumn: Int = 3, sectionGap: Int = 1, bandGap: Int = 2)
    public func assign(_ model: ExcelModel) -> CellAssignment
}
```

**Layout algorithm:**
```
Row 1: Title
Row 2: Blank

  ┌── Band 1 ──────────────────────────────┐
  │  Col C  Col D      Col F  Col G        │
  │  Inputs             Cash Flows          │
  │  Principal  100000  CF0     -50000      │
  │  Rate       0.06    CF1      15000      │
  │  Term       360     CF2      15000      │
  └─────────────────────────────────────────┘

  ┌── Band 2 ──────────────────────────────┐
  │  Col C  Col D      Col F  Col G        │
  │  Calculations       Results             │
  │  Monthly Rt  ▪      NPV     ▪          │
  │  Payment     ▪      IRR     ▪          │
  └─────────────────────────────────────────┘
```

Sections fill left-to-right in bands of `columnCount`. Each band's height is determined by the tallest section in that band. Table-registered sections expand to use the columns needed for the table grid.

### ModelExporter (enhanced)

```swift
// New private method
private static func writeTableHeaders(
    assignment: CellAssignment,
    model: ExcelModel,
    to sheet: Worksheet,
    design: DesignBundle
) {
    let headerStyle = CellStyle(font: design.labelFont)
    for (tableLabel, headerCells) in assignment.tableColumnHeaders {
        guard let table = model.table(named: tableLabel) else { continue }
        for (i, cell) in headerCells.enumerated() where i < table.columns.count {
            sheet.write(table.columns[i], to: cell.reference, style: headerStyle)
        }
    }
}
```

Called after `writeSectionHeaders` in `export()`. Additive — zero impact when `tableColumnHeaders` is empty.

---

## 5. MCP Schema

**Not applicable.** Layout strategies are compile-time selections, not MCP tool parameters. MCP consumers choose a strategy by name when calling the export tool:

```json
{
  "model": "amortization",
  "layout": "horizontal",
  "layoutOptions": {
    "startColumn": 3,
    "sectionGap": 1
  }
}
```

This schema would be implemented in a future MCP tool wrapper, not in this proposal.

---

## 6. Constraints & Compliance

| Constraint | How Addressed |
|------------|---------------|
| **Concurrency** | All strategies are `Sendable` structs with immutable properties |
| **No force unwraps** | All table/node lookups use optional chaining or guard |
| **Division safety** | No division operations in layout algorithms |
| **Swift 6** | Value types, no mutable shared state |
| **DocC** | All public APIs documented with examples |
| **Bounded iteration** | Loop counts bounded by `model.sections.count` and `model.allRefs.count` |

---

## 7. Source & API Compatibility

**Breaking changes:** Adding `tableColumnHeaders` to `CellAssignment` changes its memberwise initializer. However:
- `CellAssignment` is only constructed inside `LayoutStrategy.assign()` implementations
- All existing strategies are in our codebase (only `VerticalLayoutStrategy`)
- We add an explicit `init` with a default value for `tableColumnHeaders`, so `VerticalLayoutStrategy` compiles unchanged

**Incremental adoption:** Consumers can switch layout by passing a different strategy to `ModelExporter.export(layout:)`. Existing code passes `VerticalLayoutStrategy()` (or uses the default) and is unaffected.

---

## 8. Backend Abstraction

Not applicable. Layout computation is O(n) in node count — no GPU/Accelerate acceleration needed.

---

## 9. Dependencies

**Internal:**
- `ExcelModel`, `NodeRef`, `CellAssignment`, `ModelExporter` (all existing)
- `SwiftXLSX.CellRef` (existing dependency)

**External:** None.

---

## 10. Test Strategy

### Per-Strategy Tests (mirroring VerticalLayoutStrategyTests)

| Category | Tests |
|----------|-------|
| **Golden path** | Known model → verify specific cell positions for labels, values, section headers |
| **Empty model** | Zero sections → empty assignment |
| **Single section** | One section → correct column/row placement |
| **Multi-section** | 3+ sections → correct gaps, non-overlapping regions |
| **Table-aware** | Section with registered TableRef → grid layout with column headers, no individual labels |
| **Mixed** | Model with both table and non-table sections → correct handling of each |
| **Custom parameters** | Non-default startColumn, sectionGap, columnCount → positions shift correctly |
| **Large model** | 10+ sections → no cell collisions |
| **Edge: single-node sections** | Sections with 1 node → no off-by-one errors |

### Integration Tests

| Test | Validates |
|------|-----------|
| `HorizontalLayoutStrategy` + `ModelExporter` | Full export produces valid workbook |
| `DashboardLayoutStrategy` + `AmortizationModelBuilder` | Schedule table renders as grid |
| `DashboardLayoutStrategy` + `DCFModelBuilder` | Cash flows in dashboard grid |
| Round-trip with `ModelImporter` | Import recognizes cells placed by new strategies |

### Reference Truth

Cell positions are deterministic given input model structure. Golden-path tests use hand-computed expected positions:
- HorizontalLayoutStrategy with 3 sections, startColumn=3, sectionGap=1:
  - Section 0 labels at column 3, values at column 4
  - Section 1 labels at column 6, values at column 7
  - Section 2 labels at column 9, values at column 10
- DashboardLayoutStrategy with columnCount=2, 4 sections of sizes [3, 2, 4, 1]:
  - Band 0: sections 0-1, rows 3-7 (tallest section = 3 nodes + header + separator)
  - Band 1: sections 2-3, rows start at band 0 lastRow + bandGap

### No-Collision Property Test

For any model, verify `Set(assignment.mapping.values).count == assignment.mapping.count` (no two nodes share a cell).

---

## 11. Architecture Decision Review

- [x] Reviewed existing ADRs
- [ ] Supersedes an existing ADR? No
- [ ] Amends an existing ADR? No
- [x] New ADR required? Yes

**New ADR Draft:**
- **Title:** Table-aware layout via optional CellAssignment field
- **Category:** architecture
- **Key decision:** Table awareness is additive to `CellAssignment` (new `tableColumnHeaders` field with empty default), not a protocol change. Strategies opt in by populating the field; strategies that don't are unaffected.

---

## 12. Adversarial Review

**Strongest case for a different approach:**
A reviewer might argue that table awareness should be a separate protocol (e.g., `TableAwareLayoutStrategy: LayoutStrategy`) rather than an optional field on `CellAssignment`. This would make table support explicit at the type level and prevent ModelExporter from checking an empty dictionary on every export.

**Why we're not doing that:** A sub-protocol creates a two-tier strategy hierarchy that complicates the type signature of `ModelExporter.export(layout:)`. The dictionary check is O(1) and trivial. More importantly, every strategy *should* be able to support tables — making it opt-in via field population is simpler than requiring a protocol conformance migration.

**Where this design is most likely wrong:**
The assumption that table sections always align with registered table labels. If a builder registers a table with label "Schedule" but the section is named "Amortization Schedule", the strategy won't match them. Builders must use consistent names — this is an implicit contract.

**What an experienced critic would say:**
"You're coupling table detection to string matching between section names and table labels — that's fragile." We accept this because builders control both names, and we'll document the requirement that table labels must match section names for table-aware rendering.

---

## 13. Alternatives Considered

**Alternative 1: Single configurable strategy instead of three types**

A single `ConfigurableLayoutStrategy` with an `enum Direction { case vertical, horizontal, dashboard(columns: Int) }` parameter.

- *Advantage:* One type to maintain, one test suite
- *Disadvantage:* The `assign()` implementation becomes a large switch with three unrelated algorithms sharing nothing. Each direction has different configuration parameters that don't apply to the others.
- *Why rejected:* Separate types are clearer, independently testable, and follow the existing pattern established by `VerticalLayoutStrategy`.

**Alternative 2: Table awareness as a wrapper/decorator strategy**

A `TableAwareStrategy` that wraps any inner strategy, detects tables, and overrides their positioning.

- *Advantage:* Any strategy gets table awareness without modification
- *Disadvantage:* The wrapper must undo and redo the inner strategy's positioning for table sections, which means understanding the inner strategy's algorithm. Fragile coupling.
- *Why rejected:* Strategies are simple enough that each can handle tables directly. The decorator adds complexity without real reuse.

**Alternative 3: Extend VerticalLayoutStrategy with table awareness instead of new strategies**

- *Advantage:* Smallest diff, immediate benefit for existing users
- *Disadvantage:* Doesn't address the core complaint (everything is vertical)
- *Why rejected:* The user specifically wants layout variety. Table awareness on vertical alone doesn't solve the problem.

---

## 14. Future Directions

- A `CompactLayoutStrategy` could omit section separators and blank rows for dense output
- `VerticalLayoutStrategy` could gain table awareness as a follow-up (opt-in via init parameter)
- Multi-sheet strategies could place each section on its own worksheet
- A `FreeformLayoutStrategy` could accept explicit `(section, column, row)` placements from the caller

---

## 15. Open Questions

1. **Should DashboardLayoutStrategy auto-detect optimal `columnCount`?** Currently the caller specifies it. Auto-detection based on section count and sizes could be a future enhancement but adds complexity.
2. **Should table column headers be styled differently from section headers?** Currently both use `design.labelFont`. A future `DesignBundle` extension could add a `tableHeaderFont`.

---

## 16. Documentation Strategy

**Documentation Type:** API Docs + Narrative Article Required

**Complexity Threshold Check:**
- Combines 3+ APIs? Yes (3 strategies + extended CellAssignment + ExcelModel accessor)
- Explanation requires 50+ lines? Yes (layout algorithm descriptions with ASCII diagrams)
- Needs theory/background context? No

**Article Name:** `LayoutStrategyGuide.md`

---

## Implementation Phases

| Phase | Scope | Estimated Tests |
|-------|-------|-----------------|
| **A** | Extend `CellAssignment` + `ExcelModel.allTables` + `ModelExporter` table header writing | 5 |
| **B** | `HorizontalLayoutStrategy` (non-table sections) | 12 |
| **C** | `DashboardLayoutStrategy` (non-table sections) | 14 |
| **D** | Table-aware rendering in both new strategies | 10 |
| **E** | Integration tests (full export round-trips) | 6 |

Total: ~47 new tests across 5 phases.

---

## Proposal Review Checklist

### Architecture
- [x] Module placement follows existing structure (`Export/`)
- [x] API design follows naming conventions (Strategy suffix, init with labeled defaults)
- [x] Concurrency model is Swift 6 compliant (Sendable structs, immutable properties)
- [x] No forbidden patterns in proposed implementation
- [x] Usage examples not broken (existing code unchanged)

### Compatibility & Evolution
- [x] Source compatibility assessed (CellAssignment init gets default parameter)
- [x] Adoption path documented (pass new strategy to `ModelExporter.export`)
- [x] Future directions listed without commitments
- [x] Alternatives considered with fair assessment

### Testing & Dependencies
- [x] Test strategy covers required categories
- [x] Reference truth identified (hand-computed cell positions)
- [x] Dependencies acceptable (none new)
- [x] Open questions listed

### Adversarial Review
- [x] Counter-design articulated (sub-protocol approach)
- [x] Failure mode named (string matching between table/section labels)
- [x] Critic's objection captured with response
