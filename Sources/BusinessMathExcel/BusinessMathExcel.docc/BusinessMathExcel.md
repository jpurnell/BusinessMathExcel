# ``BusinessMathExcel``

Translate between BusinessMath computational models and Excel workbooks that carry
live formulas rather than frozen values.

## Overview

A model is built as a directed acyclic graph of typed nodes — inputs, formulas, and
outputs — connected by ``NodeRef`` identities. Nothing in the graph knows where it
will land on a sheet. Cell positions are assigned at export time by a
``LayoutStrategy``, which is what lets the same model render as a single stacked
sheet, a dashboard grid, or one worksheet per section without being rebuilt.

Export walks the graph, resolves each ``NodeFormula`` from node references into a
`FormulaAST`, and writes real Excel formulas. Import runs the same path backwards:
a workbook is read into an ``ExcelModel``, and `FormulaMapper` maps recognised
formulas back onto BusinessMath operations.

```
Single-sheet: ExcelModel -> LayoutStrategy           -> ModelExporter      -> .xlsx
Multi-sheet:  ExcelModel -> MultiSheetLayoutStrategy -> MultiSheetExporter -> .xlsx
Import:       .xlsx      -> ModelImporter            -> ExcelModel         -> BusinessMath
Recognize:    .xlsx      -> ExcelRecognizer          -> RecognizedModel    -> ModelDefinition
```

Importing and recognizing are different jobs. An import gives you every cell and tells you
nothing about what the sheet *means*; recognition recovers the accounts, the timeline, the rules
that hold in every period, and the balances that carry between them. See <doc:RecognitionGuide>.

## Topics

### Building a model

- ``ExcelModel``
- ``NodeRef``
- ``NodeFormula``

### Laying out a sheet

- ``LayoutStrategy``
- ``VerticalLayoutStrategy``
- ``CompactLayoutStrategy``
- ``HorizontalLayoutStrategy``
- ``DashboardLayoutStrategy``

### Writing and reading workbooks

- ``ModelExporter``
- ``ModelImporter``

### Recovering a model from a workbook

- <doc:RecognitionGuide>
- ``ExcelRecognizer``
- ``RecognizedModel``
- ``ModelMaterializer``
- ``TypedSourceWriter``
