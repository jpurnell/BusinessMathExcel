# BusinessMathExcel

Bidirectional translation layer between [BusinessMath](https://github.com/jpurnell/BusinessMath) computational models and Excel workbooks with live formulas. Built on [SwiftXLSX](https://github.com/jpurnell/SwiftXLSX). Pure Swift, Foundation only.

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

All translators produce Excel workbooks with live formulas (SUM, AVERAGE, PERCENTILE, PMT, etc.) so results recalculate when inputs change.

## License

MIT
