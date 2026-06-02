import BusinessMath
import SwiftXLSX

/// Builds an ``ExcelModel`` DAG for a loan amortization schedule with live Excel formulas.
///
/// The resulting model has editable inputs (principal, rate, term) and computes
/// all payment components (PMT, IPMT, PPMT) via Excel-native formulas that
/// recalculate when any input changes.
public enum AmortizationModelBuilder {

    /// Builds an amortization model from explicit loan parameters.
    ///
    /// - Parameters:
    ///   - principal: The loan amount.
    ///   - annualRate: The annual interest rate as a decimal (e.g., 0.06 for 6%).
    ///   - termMonths: The number of monthly payment periods.
    /// - Returns: An ``ExcelModel`` ready for export.
    public static func build(
        principal: Double,
        annualRate: Double,
        termMonths: Int
    ) -> ExcelModel {
        let model = ExcelModel()

        let principalRef = model.addInput(label: "Principal", value: principal)
        let rateRef = model.addInput(label: "Annual Rate", value: annualRate)
        let termRef = model.addInput(label: "Term (months)", value: Double(termMonths))

        let monthlyRateRef = model.addFormula(
            label: "Monthly Rate",
            formula: .divide(.ref(rateRef), .number(12))
        )

        let paymentRef = model.addFormula(
            label: "Monthly Payment",
            formula: .negate(.pmt(
                rate: .ref(monthlyRateRef),
                nper: .ref(termRef),
                pv: .ref(principalRef)
            ))
        )

        var tableRows: [[NodeRef]] = []
        var prevEndBalance: NodeRef?

        for period in 1...termMonths {
            let periodRef = model.addFormula(
                label: "Period \(period)",
                formula: .number(Double(period)),
                section: "Schedule"
            )

            let begBalFormula: NodeFormula
            if let prev = prevEndBalance {
                begBalFormula = .ref(prev)
            } else {
                begBalFormula = .ref(principalRef)
            }
            let begBalRef = model.addFormula(
                label: "BegBal \(period)",
                formula: begBalFormula,
                section: "Schedule"
            )

            let pmtRef = model.addFormula(
                label: "Payment \(period)",
                formula: .ref(paymentRef),
                section: "Schedule"
            )

            let interestRef = model.addFormula(
                label: "Interest \(period)",
                formula: .negate(.ipmt(
                    rate: .ref(monthlyRateRef),
                    per: .number(Double(period)),
                    nper: .ref(termRef),
                    pv: .ref(principalRef)
                )),
                section: "Schedule"
            )

            let principalPaidRef = model.addFormula(
                label: "Principal \(period)",
                formula: .negate(.ppmt(
                    rate: .ref(monthlyRateRef),
                    per: .number(Double(period)),
                    nper: .ref(termRef),
                    pv: .ref(principalRef)
                )),
                section: "Schedule"
            )

            let endBalRef = model.addFormula(
                label: "EndBal \(period)",
                formula: .subtract(.ref(begBalRef), .ref(principalPaidRef)),
                section: "Schedule"
            )

            tableRows.append([
                periodRef, begBalRef, pmtRef,
                interestRef, principalPaidRef, endBalRef
            ])
            prevEndBalance = endBalRef
        }

        model.registerTable(
            label: "Schedule",
            columns: [
                "Period", "Beginning Balance", "Payment",
                "Interest", "Principal", "Ending Balance"
            ],
            rows: tableRows
        )

        model.addOutput(
            label: "Total Payments",
            formula: .multiply(.ref(paymentRef), .ref(termRef))
        )

        model.addOutput(
            label: "Total Interest",
            formula: .subtract(
                .multiply(.ref(paymentRef), .ref(termRef)),
                .ref(principalRef)
            )
        )

        return model
    }

    /// Builds an amortization model from a `DebtInstrument`.
    ///
    /// Extracts the principal, annual rate, and term from the instrument.
    ///
    /// - Parameter instrument: The debt instrument to model.
    /// - Returns: An ``ExcelModel`` ready for export.
    public static func build(from instrument: DebtInstrument) -> ExcelModel {
        let schedule = instrument.schedule()
        return build(
            principal: instrument.principal,
            annualRate: instrument.interestRate,
            termMonths: schedule.periods.count
        )
    }
}
