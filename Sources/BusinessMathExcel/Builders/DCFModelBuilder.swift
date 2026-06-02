import SwiftXLSX

/// Builds an ``ExcelModel`` DAG for a discounted cash flow analysis.
///
/// The resulting model has editable inputs for the discount rate and each cash flow,
/// with NPV and IRR computed via Excel-native formulas.
public enum DCFModelBuilder {

    /// Builds a DCF model from a discount rate and series of cash flows.
    ///
    /// The first cash flow is treated as the initial investment (period 0),
    /// which is added to the NPV of subsequent cash flows.
    ///
    /// - Parameters:
    ///   - discountRate: The discount rate per period as a decimal (e.g., 0.10 for 10%).
    ///   - cashFlows: Cash flow amounts, starting at period 0.
    /// - Returns: An ``ExcelModel`` ready for export.
    public static func build(
        discountRate: Double,
        cashFlows: [Double]
    ) -> ExcelModel {
        guard cashFlows.count >= 2 else {
            return emptyModel(discountRate: discountRate, cashFlows: cashFlows)
        }

        let model = ExcelModel()

        let rateRef = model.addInput(label: "Discount Rate", value: discountRate)

        var cfRefs: [NodeRef] = []
        for (i, cf) in cashFlows.enumerated() {
            let label = i == 0 ? "Initial Investment" : "Year \(i) Cash Flow"
            let ref = model.addInput(label: label, value: cf, section: "Cash Flows")
            cfRefs.append(ref)
        }

        let futureRefs = Array(cfRefs.dropFirst())
        model.addOutput(
            label: "NPV",
            formula: .add(
                .ref(cfRefs[0]),
                .npv(rate: .ref(rateRef), values: futureRefs.map { .ref($0) })
            )
        )

        model.addOutput(
            label: "IRR",
            formula: .irr(cfRefs.map { .ref($0) })
        )

        return model
    }

    private static func emptyModel(discountRate: Double, cashFlows: [Double]) -> ExcelModel {
        let model = ExcelModel()
        model.addInput(label: "Discount Rate", value: discountRate)
        for (i, cf) in cashFlows.enumerated() {
            model.addInput(
                label: i == 0 ? "Initial Investment" : "Year \(i) Cash Flow",
                value: cf,
                section: "Cash Flows"
            )
        }
        return model
    }
}
