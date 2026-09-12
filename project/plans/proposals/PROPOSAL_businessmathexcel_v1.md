# Design Proposal: BusinessMathExcel v1 — Bidirectional Excel ↔ BusinessMath

> **Resolved decisions** (per user review 2026-06-01):
> - Bidirectional: import existing Excel models into BusinessMath, not just export
> - SwiftXLSX's FormulaAST is the shared representation between Excel and BusinessMath
> - Existing Excel models (e.g., negotiation models) should be parseable → mappable → extendable
> - BusinessMath primitives map to Excel function equivalents (PMT, NPV, IRR, etc.)
> - Stochastic/iterative computations (Monte Carlo, optimization) are the "extend beyond Excel" capability
> - Default styling from user's Book.xltx template

## 1. Objective

**Objective:** BusinessMathExcel is a bidirectional translation layer between Excel and BusinessMath. It does two things:

1. **Export:** Translate BusinessMath computational graphs into interactive Excel workbooks with live formulas — not static result dumps.
2. **Import:** Parse existing Excel models, map their formulas to BusinessMath operations via the FormulaAST, and extend them with capabilities beyond Excel (Monte Carlo simulation, optimization, scenario analysis).

The influence diagram (`Negotiation_Influence_Diagram.puml`) is the reference architecture: 5 decisions, 8 uncertainties, 12 deterministic calculations, 4 value nodes — all connected in a DAG. This should be buildable in BusinessMath and exportable to Excel as a live model, AND an existing Excel model with this structure should be importable into BusinessMath.

**Master Plan Reference:** This supersedes the original "result dumper" translator approach.

## 2. Motivation

**Current situation:** Four hand-written translators dump finished BusinessMath results into cells. Some have SUM/AVERAGE formulas, but the model structure is lost. No import capability exists.

**What the user wants:**
- Build a model in BusinessMath → export to Excel → business school student opens it, changes an input, watches everything recalculate
- Open an existing Excel model → parse its formulas → map to BusinessMath → run Monte Carlo on it → export enhanced model back to Excel
- The bridge between "spreadsheet user" and "programmatic financial modeling"

**Why bidirectional matters:** The user has existing Excel models (Negotiation_Model_v6.xlsx, Bedroom_Negotiation_Model.xlsx) that represent real financial decisions. These models contain formulas that express the same computations BusinessMath provides. Importing them means the user doesn't have to rebuild models from scratch — they can start from what they have, add BusinessMath's analytical power, and export back.

**The key insight:** Excel formulas and BusinessMath operations are two representations of the same computation. `=PMT(B2/12,B3*12,-B1)` and `DebtInstrument(principal:rate:term:).schedule()` compute the same thing. The FormulaAST is the Rosetta Stone between them.

## 3. Proposed Architecture

### Two Translation Directions

```
EXPORT: BusinessMath Model → ExcelModel (graph) → SwiftXLSX Workbook → .xlsx file
IMPORT: .xlsx file → SwiftXLSX Workbook → FormulaAST → BusinessMath Operations → Enhanced Model
```

### Module Structure

```
Sources/BusinessMathExcel/
├── Model/                         # Computational graph representation
│   ├── ExcelModel.swift           # DAG container: nodes + edges
│   ├── InputNode.swift            # User-editable cell (decision/assumption)
│   ├── FormulaNode.swift          # Calculated cell with FormulaAST
│   ├── OutputNode.swift           # Highlighted result cell
│   ├── NodeRef.swift              # Identity reference (resolves to CellRef at export)
│   └── NodeFormula.swift          # FormulaAST wrapper with NodeRef resolution
├── Export/                        # BusinessMath → Excel
│   ├── ModelExporter.swift        # ExcelModel → Workbook
│   ├── LayoutStrategy.swift       # How to arrange nodes on sheets
│   ├── SingleSheetLayout.swift    # All sections on one sheet
│   └── MultiSheetLayout.swift     # Each section on its own sheet
├── Import/                        # Excel → BusinessMath
│   ├── ModelImporter.swift        # Workbook → ExcelModel (preserves AST)
│   ├── FormulaMapper.swift        # FormulaAST → BusinessMath operation mapping
│   ├── FunctionRegistry.swift     # Maps Excel function names to BusinessMath equivalents
│   └── ImportResult.swift         # What was mapped, what wasn't, warnings
├── Mapping/                       # Excel ↔ BusinessMath function equivalences
│   ├── FinancialMappings.swift    # PMT↔amort, NPV↔npv, IRR↔irr, FV↔fv, PV↔pv
│   ├── StatisticalMappings.swift  # AVERAGE↔mean, STDEV↔stdDev, PERCENTILE↔percentile
│   ├── LogicalMappings.swift      # IF, AND, OR, NOT
│   └── MathMappings.swift         # ABS, ROUND, POWER, SQRT, LN, EXP
├── Builders/                      # High-level model constructors
│   ├── AmortizationModelBuilder.swift   # DebtInstrument → live PMT/IPMT/PPMT model
│   ├── DCFModelBuilder.swift            # Discounted cash flow with editable inputs
│   ├── ScenarioModelBuilder.swift       # Data table with scenarios
│   └── CustomModelBuilder.swift         # Open-ended, like the influence diagram
└── Extensions/                    # BusinessMath extensions beyond Excel
    ├── MonteCarloExtension.swift   # Add simulation to any imported model
    ├── SensitivityExtension.swift  # Run tornado/sensitivity on imported model inputs
    └── OptimizationExtension.swift # Optimize imported model's decision variables
```

### How Export Works

```swift
// 1. Build a model with BusinessMath semantics
let model = ExcelModel(name: "House Purchase Analysis")

// Decisions — editable input cells
let price = model.addInput("Purchase Price", value: 1_850_000, style: .currency)
let rate = model.addInput("Interest Rate", value: 0.065, style: .percent)
let term = model.addInput("Loan Term (years)", value: 30, style: .integer)

// Formulas — reference inputs, resolve to cell positions at export
let monthlyRate = model.addFormula("Monthly Rate",
    formula: .divide(.ref(rate), .number(12)))
let numPayments = model.addFormula("Total Payments",
    formula: .multiply(.ref(term), .number(12)))
let payment = model.addFormula("Monthly Payment",
    formula: .pmt(rate: .ref(monthlyRate), nper: .ref(numPayments), pv: .negate(.ref(price))),
    style: .currency)

// Export — NodeRefs resolve to CellRefs during layout
let workbook = ModelExporter.export(model)
try workbook.save(to: url)

// In Excel, the payment cell contains: =PMT(B4/12, B5*12, -B1)
// Change B1 (price) → payment updates automatically
```

### How Import Works

```swift
// 1. Read an existing Excel model
let workbook = try Workbook(contentsOf: negotiationModelURL)

// 2. Import into ExcelModel (preserves formula ASTs)
let model = try ModelImporter.import(workbook)

// 3. See what was mapped to BusinessMath
let result = FormulaMapper.map(model)
// result.mapped: ["Monthly P&I" → DebtInstrument.payment, "NPV" → npv()]
// result.unmapped: ["Custom Calc" → raw FormulaAST]
// result.warnings: ["Cell D15 uses INDIRECT() — cannot map"]

// 4. Extend with BusinessMath capabilities
let simulation = MonteCarloExtension.addSimulation(
    to: model,
    varying: [
        model.node(named: "Interest Rate"): .normal(mean: 0.065, stdDev: 0.01),
        model.node(named: "Appreciation Rate"): .normal(mean: 0.035, stdDev: 0.02),
    ],
    output: model.node(named: "14-Year TCO"),
    iterations: 10_000
)

// 5. Export enhanced model back to Excel
// Original model on Sheet 1 (live formulas intact)
// Monte Carlo results on Sheet 2 (raw data)
// Summary statistics on Sheet 3 (AVERAGE, STDEV, PERCENTILE referencing Sheet 2)
let enhanced = ModelExporter.export(model, extensions: [simulation])
try enhanced.save(to: enhancedURL)
```

## 4. API Surface

### ExcelModel — The Computational Graph

```swift
public final class ExcelModel: @unchecked Sendable {
    // Justification: only mutated during construction
    
    public init(name: String = "Model")
    
    // Input nodes — user-editable cells
    @discardableResult
    public func addInput(_ label: String, value: Double,
                         section: String = "Inputs",
                         style: CellStyle = .general) -> NodeRef
    
    @discardableResult
    public func addInput(_ label: String, value: String,
                         section: String = "Inputs",
                         style: CellStyle = .general) -> NodeRef
    
    // Formula nodes — computed cells referencing other nodes
    @discardableResult
    public func addFormula(_ label: String,
                           formula: NodeFormula,
                           section: String = "Calculations",
                           style: CellStyle = .general) -> NodeRef
    
    // Output nodes — highlighted results
    @discardableResult
    public func addOutput(_ label: String,
                          source: NodeRef,
                          section: String = "Results",
                          style: CellStyle = .general)
    
    // Layout control
    public func setSectionOrder(_ sections: [String])
    
    // Query
    public func node(named label: String) -> NodeRef?
    public var sections: [String] { get }
    public var nodeCount: Int { get }
}
```

### NodeFormula — FormulaAST with NodeRef Resolution

```swift
// NodeFormula wraps FormulaAST but uses NodeRef instead of CellRef.
// During export, NodeRefs are resolved to CellRefs based on layout.
public indirect enum NodeFormula: Sendable {
    // References
    case ref(NodeRef)                             // Another node in the model
    case number(Double)                           // Literal
    case text(String)                             // String literal
    
    // Arithmetic
    case add(NodeFormula, NodeFormula)
    case subtract(NodeFormula, NodeFormula)
    case multiply(NodeFormula, NodeFormula)
    case divide(NodeFormula, NodeFormula)
    case negate(NodeFormula)
    case power(NodeFormula, NodeFormula)
    
    // Excel functions (mirror FormulaAST but with NodeRefs)
    case pmt(rate: NodeFormula, nper: NodeFormula, pv: NodeFormula)
    case ipmt(rate: NodeFormula, per: NodeFormula, nper: NodeFormula, pv: NodeFormula)
    case ppmt(rate: NodeFormula, per: NodeFormula, nper: NodeFormula, pv: NodeFormula)
    case npv(rate: NodeFormula, values: [NodeRef])
    case irr(values: [NodeRef])
    case sum(nodes: [NodeRef])
    case average(nodes: [NodeRef])
    
    // Logical
    case condition(test: NodeFormula, ifTrue: NodeFormula, ifFalse: NodeFormula)
    
    // Generic function call (for Excel functions without dedicated cases)
    case function(String, [NodeFormula])
}
```

### FormulaMapper — AST → BusinessMath Mapping

```swift
public enum FormulaMapper {
    
    public static func map(_ model: ExcelModel) -> MappingResult
}

public struct MappingResult: Sendable {
    /// Nodes whose formulas were successfully mapped to BusinessMath operations
    public let mapped: [String: BusinessMathOperation]
    
    /// Nodes whose formulas couldn't be mapped (preserved as raw FormulaAST)
    public let unmapped: [String: FormulaAST]
    
    /// Warnings about formulas that may not translate correctly
    public let warnings: [MappingWarning]
}

public enum BusinessMathOperation: Sendable {
    case debtPayment(principal: NodeRef, rate: NodeRef, term: NodeRef)
    case netPresentValue(rate: NodeRef, cashFlows: [NodeRef])
    case internalRateOfReturn(cashFlows: [NodeRef])
    case futureValue(rate: NodeRef, periods: NodeRef, payment: NodeRef)
    case arithmetic(FormulaAST)  // Simple math preserved as-is
}
```

### Model Extensions — Beyond Excel

```swift
public enum MonteCarloExtension {
    public static func addSimulation(
        to model: ExcelModel,
        varying: [NodeRef: Distribution],
        output: NodeRef,
        iterations: Int,
        seed: UInt64? = nil
    ) -> ModelExtension
}

public enum Distribution: Sendable {
    case normal(mean: Double, stdDev: Double)
    case uniform(min: Double, max: Double)
    case triangular(min: Double, mode: Double, max: Double)
    case lognormal(mean: Double, stdDev: Double)
}

public protocol ModelExtension: Sendable {
    func additionalSheets(for model: ExcelModel) -> [Worksheet]
}
```

### Builders

```swift
public enum AmortizationModelBuilder {
    public static func build(
        principal: Double,
        annualRate: Double,
        years: Int,
        frequency: PaymentFrequency = .monthly
    ) -> ExcelModel
    // Creates: editable inputs (principal, rate, term)
    //          PMT formula for payment
    //          IPMT/PPMT formulas for each period
    //          SUM totals
}

public enum DCFModelBuilder {
    public static func build(
        discountRate: Double,
        cashFlows: [Double],
        labels: [String]
    ) -> ExcelModel
    // Creates: editable discount rate + cash flows
    //          NPV and IRR formulas referencing cash flow cells
}
```

## 5. MCP Schema

```json
{
  "tool": "export_model_to_excel",
  "description": "Export a BusinessMath model to an interactive Excel workbook with live formulas",
  "parameters": {
    "model_type": { "type": "string", "enum": ["amortization", "dcf", "sensitivity", "custom"] },
    "inputs": {
      "type": "array",
      "items": {
        "label": { "type": "string" },
        "value": { "type": "number" },
        "format": { "type": "string", "enum": ["currency", "percent", "integer", "general"] }
      }
    },
    "output_path": { "type": "string" }
  }
}
```

```json
{
  "tool": "import_excel_model",
  "description": "Import an existing Excel model, map formulas to BusinessMath operations",
  "parameters": {
    "input_path": { "type": "string", "description": "Path to .xlsx file" },
    "sheet_name": { "type": "string", "description": "Optional: specific sheet to import" }
  }
}
```

## 6. Constraints & Compliance

- **Concurrency:** ExcelModel is `@unchecked Sendable` (construction-only mutation). NodeFormula, NodeRef, MappingResult are value types.
- **Safety:** No force unwraps. Import errors are reported in MappingResult.warnings, not thrown. Unmapped formulas are preserved as raw AST, not dropped.
- **Dependencies:** SwiftXLSX (FormulaAST, Workbook, CellStyle) and BusinessMath (DebtInstrument, distributions, simulation). No others.

## 7. Source & API Compatibility

**Breaking:** Existing translators (AmortizationTranslator, etc.) are deprecated. They can remain as thin wrappers that construct an ExcelModel internally, for backward compatibility.

**Phase dependency:** BusinessMathExcel's import capability depends on SwiftXLSX Phase E (reader). Export works with Phase A (AST + write).

## 8. Backend Abstraction

N/A — graph construction is not compute-intensive. Monte Carlo simulation delegates to BusinessMath's existing backend.

## 9. Dependencies

- SwiftXLSX ≥ Phase A for export, ≥ Phase E for import
- BusinessMath for financial operations, distributions, simulation

## 10. Test Strategy

**Test Categories:**

- **Export round-trip:** Build ExcelModel → export → open in Excel → change input → verify recalculation (manual gate)
- **Import round-trip:** Read .xlsx → import → export → compare output
- **Formula mapping:** PMT formula → DebtInstrument mapping, verify parameters match
- **Extension output:** Monte Carlo → summary sheet → PERCENTILE formulas reference data correctly
- **Builder equivalence:** AmortizationModelBuilder output opened in Excel matches Excel's PMT/IPMT
- **Influence diagram:** Build the Negotiation_Influence_Diagram as an ExcelModel, verify all edges resolve

**Reference Truth:**
- Excel's PMT(0.065/12, 360, -500000) = $3,160.34
- User's existing Negotiation_Model_v6.xlsx as import test case
- BusinessMath's DebtInstrument.schedule() as computation reference

**Validation Trace:**
- Build amortization model → export → cell shows `=PMT(B2/12,B3*12,-B1)` → Excel evaluates to $3,160.34
- Import Negotiation_Model_v6.xlsx → FormulaMapper identifies PMT/NPV formulas → maps to BusinessMath types
- Add Monte Carlo to imported model → export → summary sheet has `=PERCENTILE('Simulation'!B2:B10001,0.05)`

## 11. Architecture Decision Review

**ADR-001: Models are DAGs of nodes, not collections of cells**
- Category: architecture
- Decision: ExcelModel is a directed acyclic graph. Nodes reference each other by identity (NodeRef), not cell position. Positions are assigned at export time by LayoutStrategy.
- Rationale: Decouples construction from layout. Same model can export to different layouts (single sheet, multi-sheet) without changing the graph.

**ADR-002: NodeFormula mirrors FormulaAST with NodeRef**
- Category: api
- Decision: NodeFormula is structurally identical to FormulaAST but uses NodeRef where FormulaAST uses CellRef. During export, NodeRefs resolve to CellRefs via the layout.
- Rationale: Type safety — you can't accidentally put a cell address in a model formula. The resolution step catches dangling references.

**ADR-003: Import preserves unmapped formulas**
- Category: architecture
- Decision: When importing an Excel model, formulas that can't be mapped to BusinessMath operations are preserved as raw FormulaAST in the model. They're not dropped or replaced.
- Rationale: Lossless import. The user can export back without losing any formulas, even ones BusinessMathExcel doesn't understand.

## 12. Adversarial Review

**Strongest case for a different approach:**
A reviewer would say: "The import path is the hard part and you're underestimating it. Real Excel models have INDIRECT references, array formulas, named ranges scoped to sheets, circular references with iteration, VBA macros that modify cells, and conditional formatting that affects behavior. Mapping PMT → DebtInstrument is the easy 5% — the other 95% of formulas in a real model are messy arithmetic that doesn't map to any BusinessMath type."

They might argue for a simpler approach: don't try to map formulas to BusinessMath types at all. Instead, treat the Excel model as a black box. Read cell values (not formulas), use those as inputs to BusinessMath operations (Monte Carlo, sensitivity), and output results alongside the original data.

**Where this design is most likely wrong:**
The assumption that formula mapping is useful at scale. For the negotiation model, most formulas are simple arithmetic (`=B5*B6`, `=B10-B11`) that doesn't map to any named BusinessMath operation. The PMT/NPV/IRR functions that map cleanly are a small fraction. The FormulaMapper may end up classifying 90% of formulas as "unmapped arithmetic" — at which point, is the mapping layer adding value?

The answer: even for unmapped formulas, the AST representation is valuable because it enables the Monte Carlo extension. To run simulation on an imported model, you need to know which cells are upstream/downstream of an input — that's a graph traversal on the AST, not a formula mapping.

**What an experienced critic would say:**
"You're building a spreadsheet engine. That's a multi-year project, not a multi-week one."
Fair. The mitigation: we're NOT building a spreadsheet engine. We don't evaluate formulas — Excel does. We parse them into an AST for graph analysis and transformation, then serialize them back out. The computation happens in BusinessMath (for extensions) or in Excel (for the base model). We never need to implement PMT ourselves — we just need to recognize it in the AST.

## 13. Alternatives Considered

**Alternative 1: Keep result dumpers, add import as value-only (no formulas)**
- Advantage: Import is trivial — just read cell values as numbers
- Disadvantage: Loses the computational graph. Can't extend the model.
- Why rejected: The whole point is preserving and extending the graph

**Alternative 2: Full spreadsheet engine (evaluate formulas in Swift)**
- Advantage: Don't need Excel at all. Run models entirely in Swift.
- Disadvantage: Reimplementing Excel's formula engine is enormous scope. Hundreds of functions, date/time systems, locale handling.
- Why rejected: Wildly out of scope. Let Excel be Excel. We translate, not replicate.

**Alternative 3: DSL approach — define models in a Swift DSL, no Excel import**
- Advantage: Clean API, no parsing complexity
- Disadvantage: User must rebuild existing models from scratch
- Why rejected: User has existing Excel models they want to import and extend

## 14. Future Directions

- **VBA analysis:** Parse VBA macros to understand event-driven logic in imported models
- **Scenario sheets:** Export multiple scenarios as separate sheets with comparison summary
- **Chart generation:** Auto-generate charts from model outputs when SwiftXLSX supports charts
- **Model validation:** Verify imported model's formula graph is acyclic, flag potential errors
- **Collaboration:** Multiple users editing the ExcelModel before export (via actor isolation)
- **Template library:** Pre-built ExcelModels for common financial analyses (DCF, LBO, comp table)

## 15. Open Questions

1. **Import scope for v1:** Should v1 import attempt to parse all formulas, or start with a whitelist of known functions (PMT, NPV, IRR, SUM, AVERAGE, IF) and treat everything else as opaque? Recommendation: whitelist approach, expand based on real-world models.

2. **Monte Carlo extension architecture:** When adding simulation to an imported model, does the simulation run in Swift (using BusinessMath) and dump results to a new sheet, or does it generate an Excel-native simulation using Data Tables? Recommendation: run in Swift — Excel's Data Tables are limited and slow for 10K+ iterations.

3. **Circular reference detection:** Excel supports circular references with iterative calculation. Should the import path detect and warn about these, or attempt to model them? Recommendation: detect and warn, do not attempt to model.

4. **Named range resolution:** Excel models heavily use named ranges. The import path needs to resolve these to cell references in the AST. Is this a SwiftXLSX responsibility (reader) or BusinessMathExcel responsibility (importer)? Recommendation: SwiftXLSX reader resolves named ranges during parsing.

## 16. Documentation Strategy

**Documentation Type:** Narrative Article Required

**Article Name:** BusinessMathExcelGuide.md

Covers:
- Vision: bidirectional Excel ↔ BusinessMath
- Export tutorial: build a model, export with live formulas
- Import tutorial: open existing .xlsx, map formulas, extend with Monte Carlo
- Function mapping reference: Excel function → BusinessMath operation table
- Builder reference: AmortizationModelBuilder, DCFModelBuilder
- Custom model building: the influence diagram example
- Extension reference: MonteCarloExtension, SensitivityExtension
- Limitations: what formulas can't be mapped, what extensions can't do
