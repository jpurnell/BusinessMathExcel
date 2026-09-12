# Reading a Spreadsheet

Recovering a runnable model from a workbook that was never written to be read by anything but Excel.

## Overview

Importing a spreadsheet is easy. ``ModelImporter`` will give you every cell, its formula, and
what Excel last computed for it, and none of that tells you what the sheet *means*. A model is
not a grid of cells: it is accounts, a timeline, rules that hold in every period, and balances
that carry between them. Recovering those is a different job, and it is what this half of the
package does.

The distinction runs through the design. `Import/` never interprets — it reads what is there.
`Recognition/` interprets and **never throws**: it produces a plan, and everything it cannot
express becomes *residue* carrying the reason. `Materialize/` is the opposite discipline — it
validates and throws, because a model built from a plan with a hole in it would run and produce
numbers.

```swift
// A three-year forecast: revenue grows, EBITDA is a margin on it.
let workbook = Workbook()
let sheet = workbook.addSheet(name: "Forecast")
for (column, year) in zip(["C", "D", "E"], ["2024", "2025", "2026"]) {
    sheet.write(year, to: "\(column)1")
}
sheet.write("Revenue", to: "A2")
sheet.write("Margin", to: "A3")
sheet.write("EBITDA", to: "A4")
for column in ["C", "D", "E"] {
    sheet.write(1_000.0, to: "\(column)2")
    sheet.write(0.4, to: "\(column)3")
    sheet.write(
        FormulaAST.multiply(.cellRef(CellRef("\(column)2")), .cellRef(CellRef("\(column)3"))),
        to: "\(column)4")
}

let plan = ExcelRecognizer.recognize(sheet, in: workbook)
let model = try ModelMaterializer.build(from: plan.model)
let solved = try model.definition.solve()

print(solved["EBITDA"]?[Period.year(2024)] ?? 0)   // 400.0
```

## What a sheet has to tell you

Five things, in order. Each stage depends on the one before it, and each reports what it could
not settle rather than guessing.

### Where the timeline is

``PeriodAxis`` finds the row (or column) of period headings. On a real model this is rarely a
row of literals: the Wharton practice model types `2023` once and computes every later year as
`=E27+1`, so an axis detector that ignored what the file recorded Excel producing would find
nothing at all. That is the common case, not the exotic one.

A sheet that reads equally well both ways yields **no** orientation, and a sheet with no axis
yields no model. A page of prose is not a model.

### Which label owns which cells

``LabeledSeries`` binds a name to the values it names, anchored on the axis rather than on
adjacency. Anchoring on the axis answers a question that is otherwise unanswerable: whether a
blank breaks a run. A blank inside a row of figures is ordinary; a blank between two blocks is
meaningful. Once the axis says which columns are periods, a blank in a period column is simply a
missing value for that period.

**A label owns a value only when no other text cell stands between them.** Real models put
several small tables side by side, and their value columns land wherever the page was laid out —
including in the timeline's own columns. Without this rule a label sweeps the whole axis and
claims figures belonging to the table on its right.

### Whether a row means one thing

``FormulaUniformity`` compares each row's formulas by shape, in R1C1 form so that a formula
filled across reads as identical everywhere. A row that disagrees with itself has no single rule,
so it cannot become an account — picking one of its shapes would be a majority vote on what the
model means.

One exception, because it is the commonest structure in modelling: a row whose **first** period
differs and whose remaining periods agree is a *seeded rollforward*, not a hand edit.

### What each formula says

``LagDecomposition`` turns a cell's formula into a period-local rule plus the carries it implies.
The whole of this stage turns on one character:

```
E50 = D52     fills across, so it means *last period*  →  a rollforward
E50 = $D$52   is pinned, so it means *this rate*       →  an assumption
```

Reading the `$` wrong turns an interest rate into a balance that carries. A reference reaching
**two** periods back is refused rather than treated as one, because treating it as one produces a
model that runs and is wrong by a period.

### What the numbers are

``UnitInference`` reads a cell's number format, which is frequently the only statement a workbook
makes about meaning: `0.4` formatted `0%` is a proportion, the same `0.4` formatted `"$"#,##0` is
money, and the label beside either may say neither.

**The format establishes the dimension, the label may sharpen it, and neither invents one.** A
format cannot separate a rate from a ratio — `0.0%` is what an interest rate, a margin and a
growth rate all carry — so where both fit, the weaker claim wins: a proportion is a `ratio`
unless the label says it is per period. Calling an interest rate a ratio is imprecise but true;
calling a margin a rate is false.

An account whose cells state nothing gets no unit, reported at `info` rather than `warning`. On
the Wharton sheet 148 of 279 cells are formatted `General`, so a workbook that formats nothing is
not defective — and a hundred warnings would bury the findings that matter.

## A sheet is a stack of blocks

The single largest thing standing between a recognized sheet and a runnable one was an assumption
nobody had written down: that a sheet *is* its timeline.

It is not. Above the model sit assumptions — usually two or three small tables side by side, each
a label with its figure beside it. They know nothing of the years below them, and their value
columns land wherever the page was laid out. On the Wharton sheet, column `D` is the at-close
column *for the timeline* and also the left table's values; column `H` is the 2026 period *and*
the middle table's values.

Two rules follow, and neither is worth anything without the other:

1. **A label owns a value only when no other text cell stands between them.**
2. **The axis governs the rows at or below its heading line.** Outside that block the anchor
   column carries no *at close* meaning, and a label with one value is a ``ScalarAssumption`` —
   an assumption that holds for every period.

Fix only the first and `Revenue growth` has no cells on the axis at all, and still vanishes.

A **What-If table** speaks for its own cells too. Excel declares one with a single marker on the
body's top-left cell and leaves the rest as cached numbers, so without knowing where it is, any
label on those rows appears to own them — the same collision, one block further right.

## What it refuses, and why that is the feature

Every stage reports rather than guesses, and the reasons are worth reading, because each is a
specific way a spreadsheet importer can produce a model that runs and is wrong:

| Refusal | What guessing would have cost |
|---|---|
| ``DiagnosticCode/nonUniformRow`` | A majority vote on which of a row's shapes is the model |
| ``DiagnosticCode/unsupportedLag`` | A model wrong by a period, running cleanly |
| ``DiagnosticCode/unseededCarry`` | An opening balance of zero — converging, and wrong from the first period |
| ``DiagnosticCode/unitConflict`` | One account meaning both a balance and a percentage |
| ``DiagnosticCode/ambiguousAssumption`` | A label's first figure taken as its only one |
| ``DiagnosticCode/unsupportedFormulaNode`` | A cached value substituted for a formula that would not translate |

The last is the rule the whole design turns on: **a formula's cached value is never substituted
for a formula that could not be translated.** The number would be right, once, and then wrong
forever after the first input changed.

## Running what you recovered

``ModelMaterializer`` builds a `ModelDefinition`, and throws on the first unresolved reference.
That is right when you want a whole model. When the question is *how much of this workbook
works*, use ``ModelMaterializer/buildResolvable(from:)``, which removes what cannot resolve and
returns it — transitively, since a model built on a dropped account is not a model.

This is refusal, not repair. Nothing is filled in.

```swift
let resolvable = try ModelMaterializer.buildResolvable(from: plan.model)
let carried = try PeriodDriver(
    definition: resolvable.model.definition,
    rollforwards: resolvable.model.rollforwards
).run(over: resolvable.model.periods)

print(carried["EBITDA"]?[Period.year(2024)] ?? 0)   // 400.0
for dropped in resolvable.dropped {
    print("\(dropped.label): \(dropped.reason)")   // nothing to drop here
}
```

Within-period circularity — interest on an average balance, swept against the cash left after
paying it — is carried through as a cycle and converged, not broken by timing. The distinction is
measurable: on a 120 draw at 10%, a correct cyclic solve accrues **11.75** where beginning-balance
timing gives 12.00. Both run and both converge.

Cross-period carry is a `Rollforward`, in data. **Within-period cycles are solved by iteration;
crossing a period is a rollforward.** Mixing them gives a model that either fails to converge or
reports every figure one period early.

## Emitting source

``TypedSourceWriter`` writes the plan as Swift: a file you can read, diff, keep in version
control, and have a compiler check.

```swift
let source = TypedSourceWriter.swiftSource(
    for: plan.model, sheetName: sheet.name, modelName: "AcmeModel")

print(source.contains("enum AcmeModel {"))   // true
```

A definition is emitted in the typed vocabulary only when every account it reads has a known
unit, every operation has an overload upstream, and the result's unit matches. Anything else is
emitted through the string API, which makes no claim — `LineItem<U>` has no untyped form, so an
account whose unit the workbook never stated cannot be given one without inventing it.

Every declaration carries the cell it came from, which is the only way to check the recognizer's
work against the workbook by hand:

```
static let revenue = LineItem<Money>("Revenue")  // ANSWER KEY!E30
```

## Measured, on a workbook nobody wrote for us

Every figure below is from the Wharton LBO Practice Model — a teaching model with a published
answer key, which makes it a rare thing: a real spreadsheet whose right answers are known.

| | |
|---|---|
| Recognition coverage | **85%** — 238 of 279 populated cells |
| Accounts recovered | 46 |
| Values matching the sheet's own | **125 of 125** |
| Published IRR | **24.67%**, reproduced |
| Published multiple of money | **3.01×**, reproduced |
| Emitted source | 167 lines, 33 typed line items |

The last row is the honest one. Of 30 emitted definitions, 10 are checked by the compiler and 20
go out through the string API — thirteen because the sheet states no unit for them, six because
`SUM` and `AVERAGE` have no typed overload upstream. Nothing is refused by the unit algebra.

One account, `Equity of PE Firm`, is dropped and named: it reads a row holding literals until the
final year and then a formula, which a model with one rule per account cannot state.

## Topics

### Reading a sheet

- ``ExcelRecognizer``
- ``RecognitionResult``
- ``RecognizedModel``
- ``Coverage``

### The stages

- ``SheetGrid``
- ``PeriodAxis``
- ``LabeledSeries``
- ``ScalarBlock``
- ``DataTableBlock``
- ``FormulaUniformity``
- ``LagDecomposition``
- ``UnitInference``

### What was recovered

- ``RecognizedAccount``
- ``RecognizedExpression``
- ``RecognizedSensitivity``
- ``Residue``
- ``Diagnostic``
- ``DiagnosticCode``

### Running it

- ``ModelMaterializer``
- ``MaterializedModel``
- ``ResolvableModel``
- ``TypedSourceWriter``
