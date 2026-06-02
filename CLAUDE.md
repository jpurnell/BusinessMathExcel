# BusinessMathExcel — Bidirectional Excel Translation Layer

Translates between BusinessMath computational models and Excel workbooks with live formulas. Pure Swift, Foundation only.

## Session Start

Read documents in this order for full context recovery:
1. `development-guidelines/00_CORE_RULES/00_MASTER_PLAN.md` — Vision and priorities
2. `development-guidelines/00_CORE_RULES/01_CODING_RULES.md` — Forbidden patterns, safety rules
3. `development-guidelines/00_CORE_RULES/09_TEST_DRIVEN_DEVELOPMENT.md` — Testing contract
4. `development-guidelines/04_IMPLEMENTATION_CHECKLISTS/CURRENT_*.md` — Active tasks (if any)
5. Latest file in `development-guidelines/05_SUMMARIES/` — Where we left off (if any)

## Development Workflow

```
0. DESIGN   -> Propose architecture (05_DESIGN_PROPOSAL.md)
1. RED      -> Write failing tests first
2. GREEN    -> Minimum code to pass
3. REFACTOR -> Clean up, keep tests green
4. DOCUMENT -> DocC comments and examples
5. VERIFY   -> swift build + swift test (zero warnings/errors)
```

## Key Rules

- No force unwraps (`!`), no `try!`, no force casts (`as!`)
- Guard clauses for all validation; early returns over nested ifs
- Division safety: always check for zero before dividing
- Swift 6 strict concurrency compliance (all types Sendable)
- All public APIs require DocC documentation

## Architecture

```
Export: ExcelModel (DAG) -> LayoutStrategy -> ModelExporter -> SwiftXLSX Workbook -> .xlsx
Import: .xlsx -> SwiftXLSX Workbook -> ModelImporter -> ExcelModel (DAG) -> FormulaMapper -> BusinessMath
```

- `ExcelModel` is a DAG of InputNode/FormulaNode/OutputNode, connected by `NodeRef` identities
- Cell positions (A1, B2) are assigned at export time by `LayoutStrategy`, not hardcoded in the model
- `NodeFormula` references other nodes by `NodeRef`, resolved to `FormulaAST` at export
- Builders (AmortizationModelBuilder, DCFModelBuilder) auto-construct models from BusinessMath types
- Extensions (MonteCarloExtension) attach simulation to any model

## Dependencies

- `SwiftXLSX` (local path `../SwiftXLSX`) — bidirectional .xlsx read/write with FormulaAST
- `BusinessMath` (local path `../BusinessMath`) — financial/statistical computation
- Both are Foundation-only; no external dependencies

## Quality Gate

`swift build && swift test` — zero warnings, zero failures.

## References

- Full guidelines: `development-guidelines/README.md`
- Coding rules: `development-guidelines/00_CORE_RULES/01_CODING_RULES.md`
- TDD contract: `development-guidelines/00_CORE_RULES/09_TEST_DRIVEN_DEVELOPMENT.md`
- SwiftXLSX source: `../SwiftXLSX/`
- BusinessMath source: `../BusinessMath/`
