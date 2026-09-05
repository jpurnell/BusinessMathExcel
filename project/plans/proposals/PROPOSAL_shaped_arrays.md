# Proposal — Shaped arrays

**Status:** Draft, awaiting approval
**Spans:** SwiftExcelCore, SwiftXLSX, SwiftExcelFunctions, BusinessMathExcel
**Filed here** because it changes the type all four packages agree on, which is the
same reason `PROPOSAL_swift_excel_architecture.md` lives here rather than in one member.

---

## 1. Objective

**Objective:** Give `CellValue.array` a shape, so a rectangle of cells stays a rectangle
from the moment it is read to the moment it is consumed.

**Master Plan Reference:** SwiftExcelCore master plan, Roadmap — *"v0.2.0 — whatever the
first real consumer proves is missing, and nothing that is merely anticipated."* This is
that: three consumers have now proved it missing, by being wrong.

This proposal began as "can we implement TRANSPOSE." Measurement moved the objective.
TRANSPOSE is the least valuable thing shape unlocks; the valuable thing is that two
functions we already ship, and that the corpus calls constantly, cannot currently be
correct.

---

## 2. Motivation

### The representation

```swift
indirect case array([CellValue])          // SwiftExcelCore/CellValue.swift:12
func values(in range: CellRange) -> [CellValue]   // CellValueProvider.swift:24
```

A flat list, documented as row-major "by convention," carrying no dimensions. And the
provider that fills it is specified as *"an array of cell values, **skipping empty
cells**"* — the reference conformance is `range.cells.compactMap { values[$0] }`.

Two independent losses, and the second compounds the first: a range's values lose their
shape, and then lose their positions, so the element count cannot even be used to guess
the shape back.

### What that costs, measured

Each of these was run against the current build, not reasoned about. The Excel column is
Excel's documented positional semantics; each should be confirmed in Excel before it
becomes a test assertion.

| Formula | Excel | Ours today |
|---|---|---|
| `INDEX(A1:A4, 3)`, `A2` empty | `30` | **`40`** |
| `VLOOKUP("b", A1:D3, 3, FALSE)` | `"b3"` | **`#N/A`** |
| `TRANSPOSE(Assumptions!B11:B32)` | a column | not implementable |

**INDEX** walks off the end of its own range whenever the range has a gap, because the
gap was deleted before INDEX ever saw it. Silent wrong number, no error.

**VLOOKUP** does not know how wide its table is, so it guesses
(`BuiltinNavigationFunctions.swift:420-437`):

```swift
// Infer number of columns: at least colIndex
// But the actual table might have more columns. We need to figure this out.
// If the total count is divisible by colIndex, use colIndex as the column count.
// Otherwise try to find the best fit.
```

The guess is a divisibility search, and the comment is candid that it is a guess. It
survives more cases than expected — `col_index_num = 2` is inherently safe, since the
answer is always the element after the key regardless of assumed width — but a
four-column table asked for column 3 divides evenly by 3, the search stops at the wrong
width, and the lookup fails outright. VLOOKUP is **87,773 calls** in the corpus, the most
called function we have.

`HLOOKUP` (`:480`) is built on the same documented assumption and is presumed to share the
defect; only VLOOKUP and INDEX were confirmed by execution.

### What the workaround costs

There is no workaround. A caller cannot repair the shape from outside, because the
information was destroyed inside the provider. The only current mitigation is to avoid
ranges with gaps and tables whose width differs from the requested column, which is not a
rule anyone can follow or check.

### What this is *not*

Honesty about the trigger: **array formulas are rare.** Sampling 572 workbooks — 250
consecutive plus a 322-workbook stride across 2,252 — found `t="array"` in **zero**. The
one workbook known to use it holds six formulas, every one a *vector* transpose:

```xml
<f t="array" ref="D55:D174">+TRANSPOSE(consol!H35:DW35)/1000</f>
<f t="array" ref="E5:Z5">+TRANSPOSE(Assumptions!B11:B32)</f>
```

So the case for this work is **not** "unlocks array formulas." It is "two shipped
functions are silently wrong, and the fix happens to also make the array family
possible." If the corpus evidence were the only argument, this proposal would be a
`#VALUE!` on TRANSPOSE and nothing else.

---

## 3. Proposed Architecture

### New files

- `SwiftExcelCore/Sources/SwiftExcelCore/CellMatrix.swift`
- `SwiftExcelCore/Tests/SwiftExcelCoreTests/CellMatrixTests.swift`
- `SwiftExcelFunctions/Sources/SwiftExcelFunctions/BuiltinArrayFunctions.swift`
- `SwiftExcelFunctions/Tests/SwiftExcelFunctionsTests/BuiltinArrayFunctionTests.swift`

### Modified files

| File | Change |
|---|---|
| `SwiftExcelCore/CellValue.swift` | `case array([CellValue])` → `case array(CellMatrix)` |
| `SwiftExcelCore/CellValueProvider.swift` | add `matrix(in:)`, with a correct default |
| `SwiftExcelFunctions/FormulaEvaluator.swift` | 5 construction sites, 2 coercion sites |
| `SwiftExcelFunctions/Builtin*.swift` | 9 destructuring sites |
| `SwiftExcelFunctions/BuiltinNavigationFunctions.swift` | delete VLOOKUP's width guess |
| `SwiftXLSX/Workbook.swift` | 1 site (non-destructuring) |
| `BusinessMathExcel/Import/ModelImporter.swift` | 2 sites (non-destructuring) |

### Blast radius, counted

```
                        source   tests
SwiftExcelCore               0       8
SwiftXLSX                    1       0
SwiftExcelFunctions         30     129
BusinessMathExcel            3       4
```

Of the 34 source sites, **20 need no edit**: 13 are `case .array:` with no binding — Swift
matches those against a case with associated values regardless of payload — and 7 are
doc-comment mentions. The work is **9 destructuring sites** and **5 construction sites**.
That is the whole migration.

### Module placement

`CellMatrix` belongs in SwiftExcelCore and nowhere else. It is vocabulary — what a
rectangle of cells *is* — and the file reader, the evaluator, and the model translator all
need to agree on it. It takes no dependency Core does not already have.

---

## 4. API Surface

```swift
/// A rectangle of cell values, in row-major order.
public struct CellMatrix: Sendable, Equatable, Hashable {

    /// The values, row-major: index `row * columns + column`.
    public let elements: [CellValue]

    public let rows: Int
    public let columns: Int

    /// Creates a matrix, or `nil` if `elements.count != rows * columns`.
    public init?(elements: [CellValue], rows: Int, columns: Int)

    /// A single row — the shape a vector argument usually has.
    public init(row elements: [CellValue])

    /// A single column.
    public init(column elements: [CellValue])

    public subscript(row: Int, column: Int) -> CellValue   // traps out of bounds
    public func element(row: Int, column: Int) -> CellValue?  // bounds-checked

    /// `true` when either dimension is 1 — the case TRANSPOSE and the lookups care about.
    public var isVector: Bool

    public func transposed() -> CellMatrix
}
```

```swift
public enum CellValue: Equatable, Hashable, Sendable {
    // ...
    indirect case array(CellMatrix)     // was: indirect case array([CellValue])
}
```

```swift
public protocol CellValueProvider {
    // ... existing requirements unchanged ...

    /// The values in a range, keeping shape and position.
    ///
    /// Empty cells are `.blank`, not absent: position is what makes the result a
    /// rectangle rather than a bag.
    func matrix(in range: CellRange) -> CellMatrix
    func matrix(in range: CellRange, inSheet: String) -> CellMatrix
}

extension CellValueProvider {
    /// Default, derived from `value(at:)` — correct for every existing conformance
    /// without any of them being edited.
    public func matrix(in range: CellRange) -> CellMatrix { /* walks range.cells */ }
}
```

The default implementation is the load-bearing idea here. Every conformance already has
`value(at:)`, and `CellRange` already knows `rowCount` and `columnCount`, so a correct
shaped read can be derived for all of them with **zero conformance edits**. Conformances
may override for performance; none has to.

`values(in:)` is kept, deprecated, and reimplemented as
`matrix(in: range).elements.filter { $0 != .blank }` — preserving its documented
blank-skipping contract exactly, so nothing that calls it changes behaviour.

### Functions this makes possible

Phase 1 (this proposal): `TRANSPOSE`, `COUNTBLANK` — the latter is not merely absent
today but *unimplementable*, since blanks never reach a function.

Later, unblocked but not proposed: `MMULT`, `MINVERSE`, `MDETERM`, `FREQUENCY`, `TREND`,
`LINEST`, `GROWTH`, and the dynamic-array family (`FILTER`, `SORT`, `UNIQUE`, `SEQUENCE`,
`XLOOKUP`). All are absent today. None is in the corpus. They are listed to show the
ceiling this raises, not to schedule them.

---

## 5. MCP Schema

Neither SwiftExcelCore nor SwiftExcelFunctions is MCP-exposed; the MCP boundary in this
family is BusinessMathExcel's. What crosses that boundary is the serialized form, so the
schema that matters is `CellMatrix`'s encoding:

**Tool description:** A rectangular block of spreadsheet values.

```json
{
  "rows": 3,
  "columns": 4,
  "elements": [
    {"kind": "text",   "value": "a"},
    {"kind": "number", "value": 1.0},
    {"kind": "blank"},
    {"kind": "error",  "value": "#N/A"}
  ]
}
```

**Parameter types:**
- `rows` (integer): row count, ≥ 0.
- `columns` (integer): column count, ≥ 0.
- `elements` (array): exactly `rows × columns` entries, row-major — index
  `row * columns + column`. Length is a validated invariant, not a convention.
- `elements[].kind` (string), exhaustively: `"number"`, `"text"`, `"bool"`, `"error"`,
  `"date"`, `"blank"`, `"formula"`, `"array"`.
- `elements[].value`: absent for `"blank"`; ISO 8601 for `"date"`; the Excel error
  literal (`#DIV/0!`, `#N/A`, `#REF!`, `#VALUE!`, `#NUM!`, `#NAME?`, `#NULL!`) for
  `"error"`.

Encoding `blank` explicitly rather than omitting it is the same decision as the type
itself: a hole in a rectangle is data.

---

## 6. Constraints & Compliance

**Concurrency:** `CellMatrix` is an immutable value type of `Sendable` members, so
`Sendable` without qualification. No `@unchecked`, no justification comment needed.

**Safety:** The failable `init?` rejects any `elements.count != rows * columns`, so an
inconsistent matrix cannot be constructed. `element(row:column:)` is bounds-checked and
returns `Optional`; the `subscript` traps, matching stdlib convention, and is the form
used only where bounds are already established.

**Division safety:** This removes a division rather than adding one — VLOOKUP's
`tableData.count / inferredCols` and its `%` search both disappear with the guess.

**No force unwraps** anywhere in the proposed surface; the failable initializer exists
precisely so callers do not reach for one.

**Recursion:** `CellValue.array` remains `indirect` and can nest. `transposed()` is
iterative. The existing recursive flatteners (`flattenNumbers`, `findFirstError`,
`flatCount`) keep their structure and their base cases.

**Unbounded ranges — the real constraint.** `matrix(in:)` must never materialize a
whole-column range. `$B:$G` is 6.3 million cells, and `DependencyGraph` already learned
this lesson (`exactEnumerationLimit = 4_096`). The proposal adopts the same bound: above
a documented cell count, `matrix(in:)` returns `#VALUE!` rather than allocating. This
constraint is inherited from a hazard the project has already been bitten by once, and it
is the thing most likely to be forgotten during implementation.

---

## 7. Source & API Compatibility

**Breaking changes: yes, and deliberately.** `CellValue.array`'s payload type changes.
This is a source-breaking change to the type three packages share.

- **SwiftExcelCore v0.3.0** — the breaking change.
- **SwiftXLSX** — 1 non-destructuring site; needs a rebuild and a pin bump, not an edit.
- **SwiftExcelFunctions** — 14 real edits.
- **BusinessMathExcel** — 2 non-destructuring sites; rebuild and pin bump.

The SwiftExcelCore master plan is explicit that *"every change here is a
three-repository release. That cost is only bearable if changes are rare."* This is the
second such change and should be argued on that basis: the alternative is not a cheaper
fix, it is shipping VLOOKUP and INDEX known-wrong.

**Incremental adoption: no**, and it should not pretend otherwise. A shaped array and a
flat one cannot coexist in one enum case. Keeping `.array([CellValue])` alongside a new
`.matrix(CellMatrix)` would force every consumer to handle both forever, which is worse
than one migration of fourteen sites.

**Type-checking risk:** No overloads introduced. `matrix(in:)` is a new name;
`values(in:)` keeps its signature and its behaviour.

**Never move a published tag.** SwiftExcelCore `v0.2.0` is consumed by three packages and
recorded in their fingerprints; this ships as `v0.3.0`.

---

## 8. Backend Abstraction

N/A. No compute-intensive path — the operations are bounded array copies. `transposed()`
on the largest permitted matrix (4,096 cells) is trivial. Should `MMULT` or `LINEST` ever
arrive, they would deserve this section; shape itself does not.

---

## 9. Dependencies

**Internal:** `CellValue`, `CellRef`, `CellRange` (already provides `rowCount` /
`columnCount`, which is what makes the default `matrix(in:)` possible).

**External:** None. SwiftExcelCore stays Foundation-only — the stated first priority of
its master plan, and this proposal does not touch it.

---

## 10. Test Strategy

**Reference truth:** Microsoft's published function semantics for `INDEX`, `VLOOKUP`, and
`TRANSPOSE`, each expected value confirmed in Excel before it becomes an assertion. The
three rows below are the regression cases; the first two are *measured current failures*,
so they will go RED before they go green — which is the point.

**Validation trace:**

| Setup | Formula | Expected | Current |
|---|---|---|---|
| `A1=10`, `A2` empty, `A3=30`, `A4=40` | `INDEX(A1:A4, 3)` | `30` | `40` |
| `A1:D3` = a/a2/a3/a4, b/b2/b3/b4, c/c2/c3/c4 | `VLOOKUP("b", A1:D3, 3, FALSE)` | `"b3"` | `#N/A` |
| `B11:B32` a column of 22 | `TRANSPOSE(B11:B32)` | 1×22 | unimplemented |

**Categories:**
- *Golden path* — the three above, plus `TRANSPOSE` of a 2-D block and of a 1×1.
- *Shape invariants* — `init?` rejects mismatched counts; `transposed().transposed()` is
  the identity; `rows`/`columns` survive a round trip through the evaluator.
- *Blank preservation* — a range with interior gaps yields `.blank` at the right index,
  and `AVERAGE`/`COUNT`/`COUNTA` over it are **unchanged**. This is the regression risk
  that matters most and it gets explicit tests, because a silent change to aggregate
  results would be far worse than the bug being fixed.
- *Bounds* — a range above the enumeration limit answers `#VALUE!` and does not allocate.
- *Edge cases* — empty range, single cell, single row, single column.

**Why the blank tests are cheap:** the consumer layer was already written correctly.
`flattenNumbers` skips `.blank` by value (`BuiltinStatsFunctions.swift:44`), `COUNT`
filters to `.number`/`.date`, and `COUNTA` excludes `.blank` explicitly. They ignore
blanks because blanks are blank, not because blanks were missing. This was checked before
the proposal was written and is the single biggest reason the change is affordable.

---

## 11. Architecture Decision Review

**ADR check:**
- [x] Reviewed for related decisions — `SwiftExcelFunctions/project/decisions/` is empty
      (`.gitkeep` only), so nothing is superseded.
- [x] Supersedes an existing ADR? No.
- [x] Amends an existing ADR? No — but it *amends a recorded decision in HANDOFF.md*:
      "References never became values. `CellValue` has no `.reference` case and does not
      need one." That decision stands and is untouched. Shape is not reference; a matrix
      is still a value.
- [x] New ADR required? **Yes** — this is the first entry in an empty log, and it is
      exactly the kind of thing the log exists for.

**New ADR draft:**
- **Title:** Cell arrays carry their own dimensions
- **Category:** api
- **Key decision:** `CellValue.array` holds a `CellMatrix` with explicit `rows` and
  `columns` and blanks preserved in place, because a rectangle whose shape must be
  re-guessed by each consumer will be guessed wrong — as VLOOKUP and INDEX both were.

---

## 12. Adversarial Review

**Strongest case for a different approach.**
Fix the two bugs without touching the shared type. INDEX could read its range through
`context.arguments` and index cells directly, never flattening; VLOOKUP could take its
width from the argument's `CellRange` the same way. Both are reachable today via
`evaluateInContext`, both are local to one file, and neither costs a three-repository
release. A reviewer would be right that this fixes the *measured* damage at a fraction of
the cost, and they might be right that it is the better trade — the array family it
forgoes is, on the evidence, worth nearly nothing.

The counter is that it fixes two call sites of a defect that lives in the type. Every
future function that consumes a range inherits the same trap and has to remember the same
workaround, and the workaround is "do not use the value you were passed, go re-read the
arguments." That is a shape system, built by hand, once per function, with no compiler
help — which is how the VLOOKUP guess came to exist in the first place.

**Where this design is most likely wrong.**
The assumption that the enumeration bound is a detail. It is not: `matrix(in:)` preserves
blanks, so it materializes the *full* rectangle where `values(in:)` materialized only the
populated cells. A range that was cheap because it was sparse becomes expensive because it
is now honest. If a corpus workbook passes a large mostly-empty range to a lookup, this
change makes it slower or turns a working formula into `#VALUE!` at the bound. That
regression is plausible, is not measured, and should be measured against the corpus
before merge rather than after.

The second-most-likely error is the deprecated `values(in:)` shim. It is specified to
filter `.blank` to preserve old behaviour — but old behaviour also dropped cells that were
*absent*, and `.blank` and absent are not identical in every conformance. If any
conformance stores explicit blanks, the shim changes its results.

**What an experienced critic would say.**
"You are making a breaking change to a type three packages share, to fix two functions,
justified by an array family your own measurement says appears in zero of 572 workbooks."

We proceed because the measured defects are in the *most-called function in the corpus*
and produce wrong numbers with no error, and because the fix removes a guess rather than
adding a mechanism — but the criticism is fair and the cheaper alternative in §13 deserves
a real answer before approval, not after.

---

## 13. Alternatives Considered

**Alternative 1 — Per-function shape recovery via `EvaluationContext`.**
INDEX, VLOOKUP and HLOOKUP each read their range from `context.arguments` and index cells
directly.
- *Advantage:* Fixes both measured bugs. No shared-type change, no three-repository
  release, no migration, lands in an afternoon.
- *Disadvantage:* The type stays lossy, so the trap stays armed for every function added
  later. Does not enable TRANSPOSE, since a transposed result still has nowhere to live.
- *Why not preferred:* It is the right fix for the bugs and the wrong fix for the cause.
  Stated plainly because it is a genuinely defensible choice, and if the answer to §12's
  critic is "the array family is worth nothing," this is what should be built instead.

**Alternative 2 — Add `.matrix(CellMatrix)` beside `.array([CellValue])`.**
- *Advantage:* Nothing breaks; no coordinated release.
- *Disadvantage:* Two representations of one concept, permanently. Every consumer handles
  both or is subtly wrong for one. The lossy case never dies because nothing forces it to.
- *Why rejected:* It converts a one-time migration of fourteen sites into an obligation on
  every future site.

**Alternative 3 — Keep flat, add a shape sidecar (`arrayShape: (Int, Int)?` on the
evaluator).**
- *Advantage:* No enum change.
- *Disadvantage:* Shape and values can drift apart, and nothing type-checks that they
  agree. Reintroduces the same class of bug one level up.
- *Why rejected:* The invariant is the whole point; splitting it from the data discards it.

**Alternative 4 — Do nothing; answer `#VALUE!` for TRANSPOSE.**
- *Advantage:* Free.
- *Disadvantage:* Leaves INDEX returning wrong numbers silently.
- *Why rejected:* Refusing to answer is honest; answering wrongly is not. The project has
  already taken this position once, with YEARFRAC's missing day counts.

---

## 14. Future Directions

- **Spilling.** Multi-cell array results have nowhere to go: `FormulaEvaluator.evaluate`
  returns one `CellValue`, and neither package mentions spill, dynamic arrays, or array
  formulas anywhere. All six real TRANSPOSE calls are top-level spills, so **this proposal
  does not make that workbook evaluate** — it makes TRANSPOSE correct when nested. Spill
  is a separate, larger design and might come next, or might never be worth it.
- **Matrix functions.** `MMULT`, `MINVERSE`, `MDETERM` could bind to BusinessMath's linear
  algebra rather than being reimplemented.
- **Dynamic arrays.** `FILTER`, `SORT`, `UNIQUE`, `SEQUENCE` could follow, though they
  need spill to be observable.
- **`CellValueProvider` overrides.** A `Workbook`-backed `matrix(in:)` could read a
  contiguous block directly instead of per-cell.

---

## 15. Open Questions

1. **Does the cheaper alternative win?** §13's Alternative 1 fixes both measured bugs for
   a fraction of the cost. The case for this proposal rests on the type being the right
   place for the invariant, not on corpus evidence — which points the other way. This is
   the decision to make before any code is written.
2. **What is the enumeration bound, and does the corpus cross it?** `DependencyGraph` uses
   4,096. Reusing it is consistent, but the two are bounding different things. Needs a
   corpus measurement of range sizes actually passed to lookups.
3. **Does any conformance store explicit `.blank`?** Decides whether the deprecated
   `values(in:)` shim is behaviour-preserving.
4. **Should `values(in:)` be deprecated or deleted?** Deprecation leaves a lossy path
   available; deletion is one more breaking change in a release that is already breaking.
5. **Is `HLOOKUP` actually affected?** Presumed from shared construction, not confirmed.
   One probe settles it.

---

## 16. Documentation Strategy

**Documentation type:** Narrative article required.

- Combines 3+ APIs? **Yes** — `CellMatrix`, `CellValue`, `CellValueProvider`.
- Explanation requires 50+ lines? **Yes** — row-major indexing, the blank convention, and
  the enumeration bound each need stating once, precisely, somewhere findable.
- Needs background context? **Yes** — why blanks are preserved is exactly the kind of
  decision that gets "tidied up" by someone who does not know it was load-bearing.

**Article name:** `WorkingWithCellMatrices.md`, in SwiftExcelCore's DocC catalogue. Named
to collide with no Swift symbol.

The article must carry the failing INDEX example. A documented invariant with a worked
example of what happens without it is the version that survives.

---

## Approval

- [ ] §15 Q1 answered — this proposal, or Alternative 1
- [ ] Enumeration bound decided and corpus-checked
- [ ] ADR drafted into `SwiftExcelFunctions/project/decisions/`
- [ ] Release order agreed: Core v0.3.0 → SwiftXLSX → SwiftExcelFunctions → BusinessMathExcel
