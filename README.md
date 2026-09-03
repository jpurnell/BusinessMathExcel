# BusinessMathExcel

Bidirectional translation layer between [BusinessMath](https://github.com/jpurnell/BusinessMath) computational models and Excel workbooks with live formulas. Built on [SwiftXLSX](https://github.com/jpurnell/SwiftXLSX). Pure Swift.

Import is a faithful structural transcription: anything it cannot represent is reported with the
cell and the construct, and a formula's cached value is never substituted for a formula that could
not be translated.

**Recognition** goes further, and is a different job. An import gives you every cell and tells you
nothing about what the sheet *means*; recognition recovers the accounts, the timeline, the rules
that hold in every period, and the balances that carry between them — then materializes a
`ModelDefinition` you can run, or emits it as Swift source a compiler can check.

Measured on the Wharton LBO Practice Model, a teaching workbook with a published answer key:
**85% of populated cells recognized, 46 accounts recovered, and 125 of 125 values matching the
sheet's own** — with its published IRR of 24.67% and 3.01× multiple of money both reproduced.

## Requirements

- Swift 6.2+
- macOS 14+ / iOS 17+

## Installation

Add BusinessMathExcel as a dependency in your `Package.swift`:

```swift
dependencies: [
    .package(path: "../BusinessMathExcel"),
]
```

## Usage

A model is a DAG of typed nodes. Cell positions are not part of the model — a
`LayoutStrategy` assigns them at export, which is why the same graph can render as a
stacked sheet, a dashboard grid, or one worksheet per section.

```swift
import BusinessMathExcel

let model = ExcelModel()
let price = model.addInput(label: "Price", value: 100)
let quantity = model.addInput(label: "Quantity", value: 5)
model.addOutput(label: "Total", formula: .multiply(.ref(price), .ref(quantity)))

let workbook = try ModelExporter.export(model, layout: VerticalLayoutStrategy())
try workbook.save(to: URL(filePath: "revenue.xlsx"))
```

`Total` arrives in Excel as `=D4*D5`, not as `500` — change a price in the sheet and the
total recalculates.

For models that come straight from BusinessMath types, the builders skip the wiring:

```swift
let model = AmortizationModelBuilder.build(
    principal: 250_000,
    annualRate: 0.065,
    termMonths: 360
)
let workbook = try ModelExporter.export(model, title: "Amortization")
```

## Legacy Translators (deprecated)

The four `*Translator` types below predate the graph architecture and are deprecated as of
0.3.0. They remain for source compatibility. New code should build an `ExcelModel` and
export it; see the replacement table in `project/master_plan.md`.

### Amortization Schedule

```swift
import BusinessMath
import BusinessMathExcel

let schedule = DebtInstrument(
    principal: 250_000,
    annualRate: 0.065,
    termMonths: 360
).schedule()

let workbook = AmortizationTranslator.workbook(from: schedule)
try workbook.save(to: URL(filePath: "amortization.xlsx"))
```

### Sensitivity Analysis

```swift
let analysis = ScenarioSensitivityAnalysis(
    inputDriver: "Revenue",
    inputValues: [800, 900, 1000, 1100, 1200],
    outputValues: [50, 75, 100, 125, 150]
)

let workbook = SensitivityTranslator.workbook(from: analysis)
try workbook.save(to: URL(filePath: "sensitivity.xlsx"))
```

### Tornado Diagram

```swift
let tornado = TornadoDiagramAnalysis(
    inputs: ["Revenue", "COGS", "Tax Rate"],
    impacts: ["Revenue": 50_000, "COGS": 30_000, "Tax Rate": 10_000],
    lowValues: ["Revenue": 80_000, "COGS": 90_000, "Tax Rate": 95_000],
    highValues: ["Revenue": 130_000, "COGS": 120_000, "Tax Rate": 105_000],
    baseCaseOutput: 100_000
)

let workbook = TornadoTranslator.workbook(from: tornado)
try workbook.save(to: URL(filePath: "tornado.xlsx"))
```

### Monte Carlo Simulation

```swift
let results = MonteCarloSimulation(/* ... */).run()
let workbook = SimulationTranslator.workbook(from: results)
try workbook.save(to: URL(filePath: "simulation.xlsx"))
```

## Architecture

```
Single-sheet: ExcelModel -> LayoutStrategy           -> ModelExporter      -> .xlsx
Multi-sheet:  ExcelModel -> MultiSheetLayoutStrategy -> MultiSheetExporter -> .xlsx
Import:       .xlsx      -> ModelImporter            -> ExcelModel         -> BusinessMath
Recognize:    .xlsx      -> ExcelRecognizer          -> RecognizedModel    -> ModelDefinition
                                                                          -> Swift source
```

Export resolves every `NodeFormula` from node references into cell-referenced Excel formulas
(SUM, AVERAGE, PERCENTILE, PMT, NPV, IRR, ...), so results recalculate when inputs change.
Import runs the same path backwards.

Recognition is layered by what each layer is allowed to do. `Import/` never interprets.
`Recognition/` interprets and **never throws** — it produces a plan, and anything it cannot
express becomes residue carrying the reason. `Materialize/` validates and **throws**, because a
model built from a plan with a hole in it would run and produce numbers.

That discipline is the point. Each refusal is a specific way an importer can produce a model that
runs and is wrong: a row that computes two ways, a reference reaching two periods back, an
opening balance nobody stated, one name meaning both a balance and a percentage.

## Documentation

```
swift package generate-documentation --target BusinessMathExcel
```

Start with the **Reading a Spreadsheet** guide, which covers recognition end to end.

100% of public APIs documented. 522 tests.

## License

MIT
