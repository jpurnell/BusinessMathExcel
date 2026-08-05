# Implementation Checklist: Custom Layout Strategies

**Feature:** HorizontalLayoutStrategy, DashboardLayoutStrategy, and table-aware layout rendering
**Design Proposal:** `project/plans/proposals/PROPOSAL_custom_layout_strategies.md`
**Started:** 2026-06-04
**Last Updated:** 2026-06-04

---

## Current Phase: Phase E — Integration and Final Quality Gate

### Completed
- [x] Phase 0: Design proposal approved
- [x] Phase A: Foundation (CellAssignment + ExcelModel + ModelExporter) — 13 tests
- [x] Phase B: HorizontalLayoutStrategy — 15 tests
- [x] Phase C: DashboardLayoutStrategy — 13 tests
- [x] Phase D: Table-aware rendering — 12 tests

---

## Phase A: Foundation (CellAssignment + ExcelModel + ModelExporter)

### 0. Design
- [x] Architecture proposed — additive `tableColumnHeaders` field on `CellAssignment`
- [x] API surface sketched — `ExcelModel.allTables`, explicit `CellAssignment.init` with default
- [x] Backward compatibility confirmed — `VerticalLayoutStrategy` unchanged

### 1. RED — Write Failing Tests
- [x] `CellAssignmentTests` — init with and without `tableColumnHeaders`
- [x] `CellAssignmentTests` — default value produces empty dictionary
- [x] `ExcelModelTests` — `allTables` returns registered tables
- [x] `ExcelModelTests` — `allTables` is empty when no tables registered
- [x] `ModelExporterTests` — table column headers written when present in assignment

### 2. GREEN — Minimum Code to Pass
- [x] Add explicit `CellAssignment.init` with `tableColumnHeaders` defaulting to `[:]`
- [x] Add `public var allTables: [String: TableRef]` to `ExcelModel`
- [x] Add `writeTableHeaders` to `ModelExporter`, call it in `export()`
- [x] Update `VerticalLayoutStrategy` to use new init (no behavior change)
- [x] Fix `writeNodes` to write values for nodes without labelMapping (table body nodes)

### 3. REFACTOR
- [x] Safety audit — no force unwraps, no forbidden patterns
- [x] All existing tests still pass (180 tests, 0 failures)

### 4. DOCUMENT
- [x] DocC for `CellAssignment.tableColumnHeaders`
- [x] DocC for `CellAssignment.init`
- [x] DocC for `ExcelModel.allTables`

### 5. VERIFY
- [x] `swift build` — zero warnings
- [x] `swift test` — zero failures (180 tests)

---

## Phase B: HorizontalLayoutStrategy

### 1. RED — Write Failing Tests
- [ ] Empty model — returns empty assignment
- [ ] Single section — labels and values in correct columns
- [ ] Multi-section — sections placed side-by-side with correct gaps
- [ ] Section header rows — each section has a header at the correct position
- [ ] Custom parameters — non-default `startColumn`, `sectionGap` shift positions
- [ ] All refs assigned — every node in `model.allRefs` appears in `mapping`
- [ ] No cell collisions — all mapped cells are unique
- [ ] Single-node section — no off-by-one errors
- [ ] Integration: `HorizontalLayoutStrategy` + `ModelExporter` produces valid workbook
- [ ] Integration: `HorizontalLayoutStrategy` + `DCFModelBuilder` exports correctly

### 2. GREEN — Minimum Code to Pass
- [ ] Create `HorizontalLayoutStrategy.swift` in `Sources/BusinessMathExcel/Export/`
- [ ] Implement `assign(_:)` — sections side-by-side, each gets a column pair
- [ ] Non-table sections: nodes stack vertically within column pair

### 3. REFACTOR
- [ ] Safety audit — no force unwraps, bounded iteration
- [ ] All tests pass (existing + new)

### 4. DOCUMENT
- [ ] DocC for `HorizontalLayoutStrategy` and all public properties
- [ ] Usage example in doc comments

### 5. VERIFY
- [ ] `swift build` — zero warnings
- [ ] `swift test` — zero failures

---

## Phase C: DashboardLayoutStrategy

### 1. RED — Write Failing Tests
- [ ] Empty model — returns empty assignment
- [ ] Single section — placed at grid position (0, 0)
- [ ] Sections fill left-to-right — 3 sections with `columnCount=2` wraps to second band
- [ ] Band height adapts — tallest section in band determines band height
- [ ] Section headers — each section has a header at the correct row
- [ ] Custom parameters — non-default `columnCount`, `startColumn`, `sectionGap`, `bandGap`
- [ ] All refs assigned — every node appears in `mapping`
- [ ] No cell collisions — all mapped cells are unique
- [ ] Single-node sections in grid — no off-by-one errors
- [ ] Many sections (10+) — correct wrapping across multiple bands
- [ ] Integration: `DashboardLayoutStrategy` + `ModelExporter` produces valid workbook
- [ ] Integration: `DashboardLayoutStrategy` + `AmortizationModelBuilder` exports correctly

### 2. GREEN — Minimum Code to Pass
- [ ] Create `DashboardLayoutStrategy.swift` in `Sources/BusinessMathExcel/Export/`
- [ ] Implement `assign(_:)` — N-column grid with band wrapping
- [ ] Non-table sections: nodes stack vertically within each grid cell

### 3. REFACTOR
- [ ] Safety audit — no force unwraps, bounded iteration
- [ ] All tests pass (existing + new)

### 4. DOCUMENT
- [ ] DocC for `DashboardLayoutStrategy` and all public properties
- [ ] Usage example with ASCII diagram in doc comments

### 5. VERIFY
- [ ] `swift build` — zero warnings
- [ ] `swift test` — zero failures

---

## Phase D: Table-Aware Rendering

### 1. RED — Write Failing Tests
- [ ] HorizontalLayoutStrategy — section with registered table renders as grid
- [ ] HorizontalLayoutStrategy — table column headers populated in `tableColumnHeaders`
- [ ] HorizontalLayoutStrategy — table body nodes omitted from `labelMapping`
- [ ] HorizontalLayoutStrategy — table section spans correct number of value columns
- [ ] DashboardLayoutStrategy — section with registered table renders as grid
- [ ] DashboardLayoutStrategy — table column headers populated
- [ ] DashboardLayoutStrategy — table body nodes omitted from `labelMapping`
- [ ] Mixed model — table and non-table sections handled correctly together
- [ ] Integration: `AmortizationModelBuilder` + table-aware strategy → grid schedule
- [ ] No-collision property: table grid cells don't overlap with other sections

### 2. GREEN — Minimum Code to Pass
- [ ] Add table detection logic to `HorizontalLayoutStrategy.assign(_:)`
- [ ] Add table detection logic to `DashboardLayoutStrategy.assign(_:)`
- [ ] Table sections: column headers placed, nodes in grid, no individual labels

### 3. REFACTOR
- [ ] Extract shared table-layout helper (if duplication warrants it)
- [ ] Safety audit — no force unwraps, bounded iteration
- [ ] All tests pass (existing + new)

### 4. DOCUMENT
- [ ] DocC for table-aware behavior on both strategies
- [ ] Document implicit contract: table label must match section name

### 5. VERIFY
- [ ] `swift build` — zero warnings
- [ ] `swift test` — zero failures

---

## Phase E: Integration Tests and Final Quality Gate

### 1. Tests
- [ ] Round-trip: export with `HorizontalLayoutStrategy` → import with `ModelImporter`
- [ ] Round-trip: export with `DashboardLayoutStrategy` → import with `ModelImporter`
- [ ] Full amortization export with table-aware dashboard layout
- [ ] Full DCF export with horizontal layout
- [ ] `MonteCarloExtension` works on workbooks from new strategies
- [ ] No-collision property test across all strategies with same model

### 2. Final Quality Gate
- [ ] `swift build` — zero warnings
- [ ] `swift test` — zero failures, all new + existing tests pass
- [ ] Safety audit — grep for `!`, `as!`, `try!`, `fatalError`, `while true`
- [ ] Doc coverage — all new public APIs documented
- [ ] CHANGELOG.md updated
- [ ] README.md updated (if applicable)
- [ ] Session summary written

---

## Module Status

| Component | Status | Tests | Docs |
|-----------|--------|-------|------|
| CellAssignment extension | Planned | 0 | No |
| ExcelModel.allTables | Planned | 0 | No |
| ModelExporter table headers | Planned | 0 | No |
| HorizontalLayoutStrategy | Planned | 0 | No |
| DashboardLayoutStrategy | Planned | 0 | No |
| Table-aware rendering | Planned | 0 | No |
| Integration tests | Planned | 0 | N/A |

---

## Notes

- `VerticalLayoutStrategy` is intentionally not modified — it preserves backward compatibility
- Table detection relies on matching `TableRef.label` to `ModelSection.name` — implicit contract
- ExcelModel uses `@unchecked Sendable` with construction-only mutation — do not add post-construction mutation to `allTables`
- Estimated ~47 new tests across all phases
