import SwiftXLSX

/// Maps ``NodeFormula`` function calls to BusinessMath operation categories.
///
/// Categorizes Excel functions found during import into financial, statistical,
/// or unknown groups. Useful for understanding what a workbook computes.
public enum FormulaMapper {

    /// A recognized financial function and its arguments.
    public struct FinancialMapping: Sendable, Equatable {

        /// The Excel function name (e.g., "PMT", "NPV", "IRR").
        public let function: String

        /// The argument formulas.
        public let arguments: [NodeFormula]
    }

    /// A recognized statistical function and its arguments.
    public struct StatisticalMapping: Sendable, Equatable {

        /// The Excel function name (e.g., "AVERAGE", "STDEV", "PERCENTILE").
        public let function: String

        /// The argument formulas.
        public let arguments: [NodeFormula]
    }

    /// The result of mapping formulas in an ``ExcelModel``.
    public struct MappingResult: Sendable {

        /// Recognized financial function calls.
        public let financialMappings: [FinancialMapping]

        /// Recognized statistical function calls.
        public let statisticalMappings: [StatisticalMapping]

        /// Function names that could not be categorized.
        public let unmappedFunctions: [String]
    }

    private static let financialFunctions: Set<String> = [
        "PMT", "IPMT", "PPMT", "FV", "PV", "NPV", "IRR", "XIRR", "XNPV",
        "RATE", "NPER", "SLN", "DB", "DDB",
    ]

    private static let statisticalFunctions: Set<String> = [
        "AVERAGE", "STDEV", "STDEVP", "VAR", "VARP",
        "PERCENTILE", "MEDIAN", "MODE",
        "COUNT", "COUNTA", "COUNTIF",
        "MIN", "MAX", "SUM",
    ]

    /// Scans an ``ExcelModel`` and categorizes all function calls.
    ///
    /// - Parameter model: The model to scan.
    /// - Returns: A ``MappingResult`` with categorized functions.
    public static func map(_ model: ExcelModel) -> MappingResult {
        var financial: [FinancialMapping] = []
        var statistical: [StatisticalMapping] = []
        var unmapped: Set<String> = []

        for ref in model.allRefs {
            guard let kind = model.kind(of: ref) else { continue }

            let formula: NodeFormula?
            switch kind {
            case .formula(let f): formula = f
            case .output(let f): formula = f
            default: formula = nil
            }

            guard let f = formula else { continue }
            collectFunctions(
                from: f,
                financial: &financial,
                statistical: &statistical,
                unmapped: &unmapped
            )
        }

        return MappingResult(
            financialMappings: financial,
            statisticalMappings: statistical,
            unmappedFunctions: Array(unmapped).sorted()
        )
    }

    private static func collectFunctions(
        from formula: NodeFormula,
        financial: inout [FinancialMapping],
        statistical: inout [StatisticalMapping],
        unmapped: inout Set<String>,
        depth: Int = 0
    ) {
        guard depth < 500 else { return }

        switch formula {
        case .function(let name, let args):
            let upperName = name.uppercased()
            if financialFunctions.contains(upperName) {
                financial.append(FinancialMapping(function: upperName, arguments: args))
            } else if statisticalFunctions.contains(upperName) {
                statistical.append(StatisticalMapping(function: upperName, arguments: args))
            } else {
                unmapped.insert(upperName)
            }
            for arg in args {
                collectFunctions(
                    from: arg, financial: &financial,
                    statistical: &statistical, unmapped: &unmapped,
                    depth: depth + 1
                )
            }

        case .add(let lhs, let rhs), .subtract(let lhs, let rhs),
             .multiply(let lhs, let rhs), .divide(let lhs, let rhs):
            collectFunctions(
                from: lhs, financial: &financial,
                statistical: &statistical, unmapped: &unmapped,
                depth: depth + 1
            )
            collectFunctions(
                from: rhs, financial: &financial,
                statistical: &statistical, unmapped: &unmapped,
                depth: depth + 1
            )

        case .negate(let expr):
            collectFunctions(
                from: expr, financial: &financial,
                statistical: &statistical, unmapped: &unmapped,
                depth: depth + 1
            )

        case .ref, .number, .text, .bool:
            break
        }
    }
}
