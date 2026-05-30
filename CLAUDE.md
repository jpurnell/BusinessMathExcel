# BusinessMathExcel — Native Swift XLSX Pipeline

Translates BusinessMath result types into Excel workbooks. Pure Swift, zero external dependencies.

## Session Start

Read documents in this order for full context recovery:
1. `development-guidelines/00_CORE_RULES/00_MASTER_PLAN.md` — Vision and priorities
2. `development-guidelines/00_CORE_RULES/01_CODING_RULES.md` — Forbidden patterns, safety rules
3. `development-guidelines/00_CORE_RULES/09_TEST_DRIVEN_DEVELOPMENT.md` — Testing contract
4. `development-guidelines/04_IMPLEMENTATION_CHECKLISTS/CURRENT_*.md` — Active tasks (if any)
5. Latest file in `development-guidelines/05_SUMMARIES/` — Where we left off (if any)

## Development Workflow

```
0. DESIGN   → Propose architecture (05_DESIGN_PROPOSAL.md)
1. RED      → Write failing tests first
2. GREEN    → Minimum code to pass
3. REFACTOR → Clean up, keep tests green
4. DOCUMENT → DocC comments and examples
5. VERIFY   → swift build + swift test (zero warnings/errors)
```

## Key Rules

- No force unwraps (`!`), no `try!`, no force casts (`as!`)
- Guard clauses for all validation; early returns over nested ifs
- Division safety: always check for zero before dividing
- Swift 6 strict concurrency compliance
- All public APIs require DocC documentation
- `SwiftXLSX` is a separate published package (github.com/jpurnell/SwiftXLSX)
- `BusinessMathExcel` depends on `SwiftXLSX` (via SPM) and `BusinessMath` (local path)

## Architecture

```
BusinessMath types → BusinessMathExcel (translation) → SwiftXLSX (XLSX writer) → .xlsx file
```

XLSX format is ZIP + XML (Open XML / OOXML). SwiftXLSX writes the XML and packages it using Foundation's compression support. No Python, no openpyxl, no external dependencies.

## Quality Gate

Run `swift build` and `swift test` before every commit. Zero warnings, zero failures.

## References

- Full guidelines: `development-guidelines/README.md`
- Coding rules: `development-guidelines/00_CORE_RULES/01_CODING_RULES.md`
- TDD contract: `development-guidelines/00_CORE_RULES/09_TEST_DRIVEN_DEVELOPMENT.md`
- BusinessMath source: `../BusinessMath/`
