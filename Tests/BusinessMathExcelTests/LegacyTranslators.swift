import BusinessMath
import SwiftXLSX
@testable import BusinessMathExcel

/// How the tests reach the four deprecated translators.
///
/// The translators are deprecated and still shipped, so they are still tested;
/// deprecating an API is a promise to keep it working until it is removed, not
/// permission to stop checking it.
///
/// Under XCTest the suites that exercise them were themselves marked
/// `@available(*, deprecated)`, which is what let them call deprecated API without
/// a warning. Swift Testing refuses that — neither `@Suite` nor `@Test` may be
/// applied to a deprecated declaration — and calling a deprecated function from
/// one that is not deprecated is a warning in a build that allows none.
///
/// So the calls go through a protocol. The requirements are not deprecated, and a
/// test calling one names nothing that is. The witnesses in ``ShippedTranslators``
/// are deprecated, and they are the only places in the test target that touch the
/// old API: the deprecation is acknowledged once, where the call is made, rather
/// than on every suite that wants the result.
///
/// A `nil` name means "let the translator use its default", so the defaults stay
/// under test rather than being restated here.
protocol LegacyTranslating: Sendable {
    func amortizationWorkbook(from schedule: AmortizationSchedule, sheetName: String?) -> Workbook
    func sensitivityWorkbook(from analysis: ScenarioSensitivityAnalysis, sheetName: String?) -> Workbook
    func sensitivityWorkbook(from analyses: [ScenarioSensitivityAnalysis], sheetName: String?) -> Workbook
    func simulationWorkbook(from results: SimulationResults, title: String?) -> Workbook
    func tornadoWorkbook(from analysis: TornadoDiagramAnalysis, sheetName: String?) -> Workbook
}

extension LegacyTranslating {
    func amortizationWorkbook(from schedule: AmortizationSchedule) -> Workbook {
        amortizationWorkbook(from: schedule, sheetName: nil)
    }

    func sensitivityWorkbook(from analysis: ScenarioSensitivityAnalysis) -> Workbook {
        sensitivityWorkbook(from: analysis, sheetName: nil)
    }

    func sensitivityWorkbook(from analyses: [ScenarioSensitivityAnalysis]) -> Workbook {
        sensitivityWorkbook(from: analyses, sheetName: nil)
    }

    func simulationWorkbook(from results: SimulationResults) -> Workbook {
        simulationWorkbook(from: results, title: nil)
    }

    func tornadoWorkbook(from analysis: TornadoDiagramAnalysis) -> Workbook {
        tornadoWorkbook(from: analysis, sheetName: nil)
    }
}

/// The translators as shipped.
struct ShippedTranslators: LegacyTranslating {
    @available(*, deprecated)
    func amortizationWorkbook(from schedule: AmortizationSchedule, sheetName: String?) -> Workbook {
        guard let sheetName else { return AmortizationTranslator.workbook(from: schedule) }
        return AmortizationTranslator.workbook(from: schedule, sheetName: sheetName)
    }

    @available(*, deprecated)
    func sensitivityWorkbook(from analysis: ScenarioSensitivityAnalysis, sheetName: String?) -> Workbook {
        guard let sheetName else { return SensitivityTranslator.workbook(from: analysis) }
        return SensitivityTranslator.workbook(from: analysis, sheetName: sheetName)
    }

    @available(*, deprecated)
    func sensitivityWorkbook(from analyses: [ScenarioSensitivityAnalysis], sheetName: String?) -> Workbook {
        guard let sheetName else { return SensitivityTranslator.workbook(from: analyses) }
        return SensitivityTranslator.workbook(from: analyses, sheetName: sheetName)
    }

    @available(*, deprecated)
    func simulationWorkbook(from results: SimulationResults, title: String?) -> Workbook {
        guard let title else { return SimulationTranslator.workbook(from: results) }
        return SimulationTranslator.workbook(from: results, title: title)
    }

    @available(*, deprecated)
    func tornadoWorkbook(from analysis: TornadoDiagramAnalysis, sheetName: String?) -> Workbook {
        guard let sheetName else { return TornadoTranslator.workbook(from: analysis) }
        return TornadoTranslator.workbook(from: analysis, sheetName: sheetName)
    }
}

/// The translators, seen only through the protocol.
let legacy: any LegacyTranslating = ShippedTranslators()
