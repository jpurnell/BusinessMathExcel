# Proposal — The SwiftExcel package family

**Status:** draft, 2026-09-04. Spans four repositories, so it lives here and is referenced from
each rather than duplicated.

---

## 1. What is being separated, and why

Today `SwiftXLSX` holds four unrelated things: the vocabulary of a spreadsheet (`CellValue`,
`CellRef`, `FormulaAST`), the file format (lexer, parser, ZIP, reader/writer), presentation
(styles, fonts, fills), and — discovered late in this analysis — **a working function library and
evaluator: 73 Excel functions across eight `Builtin*Functions` files, plus `FunctionRegistry` and
`FormulaEvaluator`.**

Each changes for a different reason. The file format changes when the OOXML spec does. The
function library changes when Excel adds or renames a function. Presentation changes when someone
wants a different look. They are bundled only because they arrived together.

The split is worth making for one concrete reason beyond tidiness: **the function library is
independently licensable and independently useful.** A Swift implementation of Excel's function
surface has an audience that does not care about ZIP archives, and a consumer who only wants to
load a file should not compile 153,245 lines of BusinessMath to do it.

## 2. The packages

| Package | Depends on | Holds |
|---|---|---|
| **SwiftExcelCore** | Foundation | `CellValue`, `CellRef`, `CellRange`, `CellAddress`, `SheetReference`, `ExcelError`, `EvalError`, `FormulaAST`, `CellValueProvider` (protocol), `NamedRange` |
| **SwiftXLSX** | Core, SwiftZIP | `FormulaLexer`, `FormulaParser`, `FormulaToken`, `FormulaParseError`, `FormulaSerializer`, `Workbook`, `Worksheet`, `Reader/*`, `SharedStrings`, styles, `DependencyGraph`, the `Workbook`-backed provider |
| **SwiftExcelFunctions** | Core, **BusinessMath** | every `Builtin*Functions`, `FunctionRegistry`, `ExcelFunction`, `FormulaEvaluator` |
| **BusinessMath** | — | the mathematics, and only the mathematics |

Later, and not yet: a layout/theming package, and a **SwiftExcel** umbrella composing the family
for applications — the motivating one being a CLI that evaluates a workbook for correctness.

### 2.1 Three checks that had to pass, and did

Verified before writing this, because each would have sunk the split:

1. **The grid functions do not need SwiftXLSX.** `CellValueProvider` is already a *protocol* over
   `CellRef`/`CellRange` → `CellValue` — Core types only. `VLOOKUP`, `INDEX`, `MATCH` live in
   SwiftExcelFunctions against the protocol; the `Workbook`-backed conformance stays in SwiftXLSX.
2. **Nothing in storage depends on the evaluator.** `Workbook`, `Worksheet`, `FormulaSerializer`
   and `Reader/*` contain no reference to `FormulaEvaluator` or `FunctionRegistry`. Removing them
   breaks nothing internally.
3. **BusinessMathExcel does not use SwiftXLSX's evaluator.** Every reference is to
   `FormulaEvaluator<Double>`, which is BusinessMath's. The extraction is invisible to the only
   consumer.

So this is a reorganisation of working code, not a construction project.

### 2.2 What SwiftExcelFunctions can do alone

Hand it a `FormulaAST` and any `CellValueProvider` and it evaluates — no file, no ZIP, no
workbook. That is the licensing story, and it is also the **test surface**: `PsiTriangular`'s
argument order and `PsiLogNormal`'s parameterisation can be asserted against published values
without opening a spreadsheet.

### 2.3 Where the functions themselves come from

`SwiftExcelFunctions` is the single registry a caller sees; a caller never needs to know which
package computes a given name. Underneath:

- **Excel semantics** — error propagation, coercion, `IF`/`IFERROR`, argument arity — is the
  package's own.
- **Grid operations** — `VLOOKUP`, `INDEX`, `MATCH`, `OFFSET` — are its own, via
  `CellValueProvider`.
- **Primitives** — trigonometry, logs, rounding, dates, text — are Foundation and swift-numerics.
- **Mathematics** — distributions, statistics, financial — delegates to BusinessMath. Never
  reimplemented, for the reason BusinessMath's own registry states: *"a second NPV that could
  disagree with the first."*

Small quantities that are genuinely mathematics but currently absent — `RATE`, `NPER`,
depreciation — go **into BusinessMath** with Swift-appropriate signatures, and Excel's sign
conventions are applied at the binding. That is what BusinessMath already does for `PMT`, which
binds to `-payment(...)`.

## 3. A consequence to act on

If SwiftExcelFunctions is the Excel function authority, **BusinessMath's
`FormulaEvaluator.Function` becomes a second Excel registry in the same dependency chain** — two
tables that can disagree about `AVERAGE` or `NPV`.

Narrow it to what it is actually for: the period-local `ModelDefinition` grammar, where
aggregating down a column is deliberately inexpressible. It is not a general Excel surface and
should stop looking like one.

## 4. Sequencing

Never move a published tag — a retagged `v0.11.0` broke SwiftPM's trust-on-first-use fingerprints
downstream earlier in this work.

1. **SwiftExcelCore** — new package. Additive, breaks nothing.
2. **SwiftXLSX 0.12.0** — depends on Core, sheds the functions. Breaking, but the only consumer
   does not use them.
3. **SwiftExcelFunctions** — new package. Absorbs the 73, adds the BusinessMath tier.
4. **BusinessMath** — the missing mathematics.

**Core must stay stable.** Three packages depend on it, so every change to it is a three-repo
release. It is value types and one protocol; keep it that way.

**Independent of all of this:** 53% of the corpus's formulas fail to parse, in SwiftXLSX's
`FormulaParser`. That work is unaffected by the reorganisation, is the highest-value item
available, and should not wait for it.

## 5. Coverage — what SwiftExcelFunctions has to reach

Against Microsoft's 519 documented worksheet functions, with SwiftXLSX's 73 inherited:

| Marking | Count | Meaning |
|---|---|---|
| `have` | **72** | SwiftXLSX implements it; moves across as-is |
| `bindable` | **84** | BusinessMath computes it; needs an Excel-facing binding |
| `new` | 6 | verified absent everywhere |
| `out of scope` | 10 | cube and web — need an OLAP connection or the network |
| `unreviewed` | 347 | no evidence either way; **not** the same as absent |

Bindable by category: 51 statistical, 11 financial, 10 math, 7 compatibility. The statistical
block is the prize — `NORM.DIST`, `NORM.INV`, `T.DIST`, `F.DIST`, `CHISQ.DIST`, `BETA.DIST`,
`BINOM.DIST`, `POISSON.DIST`, `CORREL`, `LINEST`, `TREND`, `GROWTH`, `SKEW`, `KURT` and the whole
dotted `STDEV`/`VAR`/`COVARIANCE` family are all computed today and reachable from no formula.

For Risk Solver's 295: **50 bindable**, 13 annotations that are role declarations rather than
functions, 232 unreviewed.

Full matrix: `excel_function_coverage_matrix.tsv`.

### 5.1 The `unreviewed` bucket is honest, not lazy

347 rows carry no evidence in either direction. Most are math, engineering and text — largely
Foundation, libm and swift-numerics, so a large share will resolve to near-free rather than to
work. They are not marked `new` because absence of an annotation is not absence of an
implementation, and marking them so would commission work that may already be done.

**The first pass of this matrix got exactly that wrong** and is worth recording: substring
matching claimed `NOMINAL` was covered by `minimize` and `PRICE` by `CommodityCollar.payoff`, and
prose describing *"Excel FV(rate,nper,pmt,…)"* leaked `RATE` and `NPER` as though they were
implemented. It reported 148 bindable. Requiring explicit evidence, then checking against 18
functions analysed by hand, cut it to 84 — and all 18 now agree.

## 6. What this does to BusinessMathExcel

**It sharpens, and it shrinks.**

BusinessMathExcel currently does two unrelated jobs. One is Excel-general — building a graph over
cells, laying out a workbook, exporting. The other is interpretive — reading a spreadsheet as a
*financial model* with periods, accounts, rules and carries, and emitting a `ModelDefinition`.

The first job belongs to the family above. The second is BusinessMathExcel, and nothing else in
the stack does it or should.

| Moves out | Stays |
|---|---|
| graph construction and evaluation | `PeriodAxis`, `LabeledSeries`, `ScalarBlock`, `LagDecomposition`, `ShapeRun` |
| `GraphPartition` — cell roles from topology | `ModelMaterializer` → `ModelDefinition` |
| `LayoutStrategy` and the exporters | `TypedSourceWriter` → Swift source |

So it is **not** the umbrella. The umbrella is Excel-shaped: its vocabulary is cells, formulas,
sheets, styles. BusinessMathExcel is model-shaped: its vocabulary is periods, accounts, decision
variables, objectives. It becomes a *consumer* of the family rather than the owner of the
pipeline, and the bidirectional claim survives intact — spreadsheet → `ModelDefinition` and back,
with both directions passing through a graph that now lives below it.

The name gets more accurate, not less: it is the bridge between BusinessMath and Excel, and after
this it is only that.
