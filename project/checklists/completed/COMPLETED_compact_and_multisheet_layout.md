# Implementation Checklist: Compact and Multi-Sheet Layout Strategies

**Feature:** CompactLayoutStrategy (table-aware) and MultiSheetLayoutStrategy with MultiSheetExporter
**Design Proposal:** `project/plans/proposals/PROPOSAL_compact_and_multisheet_layout.md`
**Started:** 2026-06-06
**Last Updated:** 2026-06-06

---

## Current Phase: Phase E — Integration + Final Quality Gate

### Completed
- [x] Phase 0: Design proposal approved
- [x] Phase A: CompactLayoutStrategy — 14 tests
- [x] Phase B: MultiSheetAssignment + SheetCell — 6 tests
- [x] Phase C: MultiSheetLayoutStrategy — 9 tests
- [x] Phase D: MultiSheetExporter — 8 tests

---

## Phase A: CompactLayoutStrategy (table-aware)

### 1. RED — Write Failing Tests
- [x] Empty model → empty assignment
- [x] Single section → labels/values at correct positions, no separator
- [x] Multi-section → sections flow without blank rows between them
- [x] Section headers → correct rows with no gaps
- [x] Custom label/value columns → positions shift correctly
- [x] All refs assigned → every node in model appears in mapping
- [x] No cell collisions → all mapped cells unique
- [x] Comparison: compact produces fewer rows than vertical for same model
- [x] Table-aware: registered table renders as grid
- [x] Table-aware: column headers populated in `tableColumnHeaders`
- [x] Table-aware: table body nodes omitted from `labelMapping`
- [x] Table-aware: mixed table and non-table sections handled correctly
- [x] Integration: CompactLayoutStrategy + ModelExporter → valid workbook
- [x] Integration: CompactLayoutStrategy + AmortizationModelBuilder → correct table output

### 2. GREEN — Minimum Code to Pass
- [x] Create `CompactLayoutStrategy.swift` in `Sources/BusinessMathExcel/Export/`
- [x] Implement `assign(_:)` — vertical stacking, no blank separator rows
- [x] Add table detection: `model.table(named: section.name)` → grid rendering

### 3. REFACTOR
- [x] Safety audit — no force unwraps, bounded iteration
- [x] All tests pass (existing + new)

### 4. DOCUMENT
- [x] DocC for `CompactLayoutStrategy` and all public properties

### 5. VERIFY
- [x] `swift build` — zero warnings
- [x] `swift test` — zero failures (234 tests)

---

## Phase B: MultiSheetAssignment + SheetCell Types

### 1. RED — Write Failing Tests
- [x] SheetCell equality and hashing
- [x] MultiSheetAssignment sheets dictionary populated per section
- [x] MultiSheetAssignment sheetOrder preserves insertion order
- [x] MultiSheetAssignment globalMapping contains all nodes with correct sheet names
- [x] Empty model → empty assignment

### 2. GREEN — Minimum Code to Pass
- [x] Create `MultiSheetAssignment.swift` in `Sources/BusinessMathExcel/Export/`
- [x] Implement `SheetCell` struct (Sendable, Equatable, Hashable)
- [x] Implement `MultiSheetAssignment` struct

### 3. REFACTOR
- [x] Safety audit
- [x] All tests pass

### 4. DOCUMENT
- [x] DocC for `SheetCell`, `MultiSheetAssignment`

### 5. VERIFY
- [x] `swift build` — zero warnings
- [x] `swift test` — zero failures

---

## Phase C: MultiSheetLayoutStrategy

### 1. RED — Write Failing Tests
- [x] Empty model → empty assignment
- [x] Single section → one sheet with correct assignment
- [x] Multi-section → one sheet per section
- [x] Custom sheet names → override map applied
- [x] Per-sheet layout respected → nodes positioned per inner strategy
- [x] Global mapping → all nodes present with correct sheet+cell
- [x] Section with table → table-aware per-sheet layout preserved
- [x] Default sheet names use section names
- [x] Single section assignment has correct mapping

### 2. GREEN — Minimum Code to Pass
- [x] Create `MultiSheetLayoutStrategy.swift` in `Sources/BusinessMathExcel/Export/`
- [x] Implement `assign(_:)` — one section per sheet, delegates to per-sheet layout
- [x] Build `MultiSheetAssignment` with globalMapping

### 3. REFACTOR
- [x] Safety audit
- [x] All tests pass

### 4. DOCUMENT
- [x] DocC for `MultiSheetLayoutStrategy` and all public properties

### 5. VERIFY
- [x] `swift build` — zero warnings
- [x] `swift test` — zero failures

---

## Phase D: MultiSheetExporter

### 1. RED — Write Failing Tests
- [x] Single-section model → one sheet in workbook
- [x] Multi-section model → N sheets in workbook
- [x] Cross-sheet formula → resolves to `SheetReference` in output
- [x] Same-sheet formula → resolves to normal `CellRef`
- [x] Title written on each sheet
- [x] Custom sheet names applied
- [x] Table headers written when present
- [x] Integration: full export with DCFModelBuilder

### 2. GREEN — Minimum Code to Pass
- [x] Create `MultiSheetExporter.swift` in `Sources/BusinessMathExcel/Export/`
- [x] Implement `export()` — creates sheets, writes per-sheet content
- [x] Implement cross-sheet formula resolution (inline in exporter, no NodeFormula changes)

### 3. REFACTOR
- [x] Safety audit
- [x] All tests pass

### 4. DOCUMENT
- [x] DocC for `MultiSheetExporter` and all public APIs

### 5. VERIFY
- [x] `swift build` — zero warnings
- [x] `swift test` — zero failures (257 tests)

---

## Phase E: Integration + Final Quality Gate

### 1. Tests
- [x] Full amortization export with table-aware compact layout (Phase A integration test)
- [x] Full DCF export with multi-sheet layout (Phase D integration test)
- [x] Cross-sheet formulas reference correct sheet names and cells (Phase D)
- [ ] MonteCarloExtension compatibility check

### 2. Final Quality Gate
- [x] `swift build` — zero warnings
- [x] `swift test` — zero failures (257 tests, 0 failures)
- [x] Safety audit — no forbidden patterns in new code
- [x] Doc coverage — all new public APIs documented
- [ ] CHANGELOG.md updated
- [ ] Session summary written

---

## Module Status

| Component | Status | Tests | Docs |
|-----------|--------|-------|------|
| CompactLayoutStrategy | Complete | 14 | Yes |
| SheetCell | Complete | 2 | Yes |
| MultiSheetAssignment | Complete | 4 | Yes |
| MultiSheetLayoutStrategy | Complete | 9 | Yes |
| MultiSheetExporter | Complete | 8 | Yes |
| Integration tests | Partial | included above | N/A |

---

## Notes

- CompactLayoutStrategy is table-aware (unlike VerticalLayoutStrategy)
- MultiSheetExporter does NOT modify NodeFormula — cross-sheet resolution is inline in the exporter
- SwiftXLSX already has FormulaAST.sheetRef(SheetReference) — no SwiftXLSX changes needed
- Table detection uses string matching: TableRef.label must match ModelSection.name
- NodeFormula.sheetRef case was dropped per adversarial review — exporter handles cross-sheet without model changes

---

**Last Updated:** 2026-06-06
