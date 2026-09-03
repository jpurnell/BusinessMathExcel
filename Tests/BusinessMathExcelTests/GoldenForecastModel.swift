// Generated from Forecast by BusinessMathExcel.
//
// Each declaration names the cell it came from. That is the only way to
// check this file against the workbook by hand, which is the first thing
// anyone reading it will want to do.

import BusinessMath
import Foundation

/// The model recognized from Forecast.
enum GoldenForecast {

    // MARK: - Timeline

    static let periods: [Period] = [
    Period.year(2024),
    Period.year(2025),
    Period.year(2026),
]

    // MARK: - Line items

    static let revenueClosing = LineItem<Money>("Revenue Closing")  // Forecast!C6
    static let ebitda = LineItem<Money>("EBITDA")  // Forecast!C7
    static let revenueGrowth = LineItem<Rate>("Revenue growth")  // Forecast!A2
    static let ebitdaMargin = LineItem<Ratio>("EBITDA margin")  // Forecast!A3
    static let revenue = LineItem<Money>("Revenue")  // Forecast!C6

    // MARK: - Data

    static let inputs: [String: TimeSeries<Double>] = [
        "Revenue growth": TimeSeries(periods: [Period.year(2024), Period.year(2025), Period.year(2026)], values: [0.15, 0.15, 0.15]),  // Forecast!A2
        "EBITDA margin": TimeSeries(periods: [Period.year(2024), Period.year(2025), Period.year(2026)], values: [0.4, 0.4, 0.4]),  // Forecast!A3
    ]

    // MARK: - Definitions

    /// The model as the sheet defines it.
    static func definition() -> ModelDefinition<Double> {
        var model = ModelDefinition<Double>(inputs: inputs)
        model = model.defining(revenueClosing, as: (revenue.expr * ratio(1.15)))
            // Forecast!C6
        model = model.defining(ebitda, as: (revenue.expr * ebitdaMargin.expr))
            // Forecast!C7
        return model
    }

    // MARK: - Running

    /// Every account, supplied and derived, over the timeline.
    static func run() throws -> [String: TimeSeries<Double>] {
        let model = definition()
        try model.validateUnits()

        let driver = PeriodDriver(
            definition: model,
            rollforwards: [
                Rollforward(opening: "Revenue", closing: "Revenue Closing", seed: 1000000.0),
            ]
        )
        return try driver.run(over: periods)
    }
}
