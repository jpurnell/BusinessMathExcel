import Foundation
import SwiftExcelCore
import SwiftExcelFunctions
import SwiftXLSX

/// What a workbook's own formulas say is uncertain.
///
/// `ExcelRecognizer` reads *model* structure — where the period axis runs, which
/// rows are series, how a formula lags its neighbours. It has no way to tell a
/// hard-coded assumption from a random draw, because topologically they are the
/// same thing: a cell fed by nothing, feeding something.
///
/// A workbook built with Risk Solver already answers that, in its formulas. A cell
/// calling `PsiTriangular(80, 100, 130)` is an *uncertain input* and says so; a cell
/// carrying `PsiOutput()` is a reported result and says so. Reading that is
/// recognition rather than evaluation — no add-in, no seed, no simulation engine —
/// which matters because an archived model has none of those.
///
/// ```swift
/// import SwiftXLSX
///
/// let workbook = Workbook()
/// let sheet = workbook.addSheet(name: "Model")
/// sheet.writeFormula("_xll.PsiTriangular(80,100,130)", to: "B2")
/// sheet.writeFormula("SUM(B2:B4)+_xll.PsiOutput()", to: "B5")
///
/// let found = SimulationInputs.survey(workbook, sheet: "Model")
/// print(found.inputCount)                            // 1
/// print(found.outputs.map(\.reference))              // ["B5"]
/// ```
public enum SimulationInputs {

    /// Surveys one sheet for the cells that draw and the cells that report.
    ///
    /// - Parameters:
    ///   - workbook: The workbook to read.
    ///   - sheet: The sheet name to survey.
    /// - Returns: The draws, the outputs, and any property function left unmodelled.
    public static func survey(_ workbook: Workbook, sheet: String) -> ModelSurvey {
        let provider = WorkbookValueProvider(workbook: workbook, currentSheet: sheet)
        return ModelSurveyor().survey(provider)
    }

    /// Whether a sheet carries any simulation at all.
    ///
    /// Cheaper to ask than to act on: most sheets in a workbook are not models, and a
    /// recogniser that runs the whole pipeline on every one of them wastes most of
    /// its work.
    ///
    /// - Parameters:
    ///   - workbook: The workbook to read.
    ///   - sheet: The sheet name to test.
    /// - Returns: `true` when the sheet holds at least one draw or one output marker.
    public static func isSimulated(_ workbook: Workbook, sheet: String) -> Bool {
        let found = survey(workbook, sheet: sheet)
        return !found.uncertain.isEmpty || !found.outputs.isEmpty
    }
}
