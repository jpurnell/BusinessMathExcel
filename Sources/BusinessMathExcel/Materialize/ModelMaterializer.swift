import BusinessMath
import RealModule
import SwiftXLSX

/// Why a plan could not be built.
///
/// Recognition never throws; materialization does. A `ModelDefinition` built from
/// a plan with a hole in it would run, and produce numbers, and those numbers
/// would be wrong in a way nothing downstream could detect.
public enum MaterializationError: Error, Sendable, Equatable {

    /// A formula reads an account the plan neither supplies nor derives.
    ///
    /// Names both sides: which account carries the bad formula, and what it was
    /// looking for. The second is what makes the gap actionable rather than merely
    /// reported.
    case unresolvedReference(account: String, missing: String)

    /// A formula the evaluator cannot parse.
    case invalidFormula(account: String, underlying: String)

    /// Two accounts claim the same name.
    case duplicateAccount(String)

    /// An account is both supplied and derived — a model that disagrees with itself.
    case suppliedAndDerived(String)
}

/// A plan, built.
public struct MaterializedModel: Sendable {

    /// The model, ready to evaluate.
    public let definition: ModelDefinition<Double>

    /// The carries between periods, for a ``PeriodDriver``.
    public let rollforwards: [Rollforward<Double>]

    /// The timeline the model runs over.
    public let periods: [Period]
}

/// Builds a `ModelDefinition` from a recognized plan.
///
/// Named for what it does rather than for the plan's shape: `BusinessMath` already
/// exports a `ModelBuilder` for its fluent API, and two types with one name in a
/// package that imports both is a collision waiting for whoever writes the next
/// `import`.
///
/// Validates before constructing. Every check here catches something that would
/// otherwise surface as a plausible number rather than an error — an account read
/// but never defined, a name claimed twice, a formula that does not parse.
public enum ModelMaterializer {

    /// Builds a plan.
    ///
    /// - Parameter plan: The recognized model.
    /// - Returns: The definition, its rollforwards, and the timeline.
    /// - Throws: ``MaterializationError``.
    public static func build(from plan: RecognizedModel) throws -> MaterializedModel {
        var seen: Set<String> = []
        for account in plan.accounts {
            guard seen.insert(account.name).inserted else {
                throw MaterializationError.duplicateAccount(account.name)
            }
        }

        var inputs: [String: TimeSeries<Double>] = [:]
        var derived: [(name: String, formula: String)] = []

        for account in plan.accounts {
            switch (account.formula, account.values) {
            case (let formula?, nil):
                derived.append((account.name, formula))
            case (nil, let values?):
                let ordered = plan.periods.filter { values[$0] != nil }
                inputs[account.name] = TimeSeries(
                    periods: ordered, values: ordered.compactMap { values[$0] })
            case (_?, _?):
                throw MaterializationError.suppliedAndDerived(account.name)
            case (nil, nil):
                continue
            }
        }

        // An opening account is supplied by the driver, one period at a time, so
        // the model knows it even though nothing in the plan defines it.
        let openings = Set(plan.rollforwards.map(\.opening))
        let known = Set(inputs.keys).union(derived.map(\.name)).union(openings)

        for entry in derived {
            let reads: Set<String>
            do {
                reads = try FormulaEvaluator<Double>.accountNames(in: entry.formula)
            } catch {
                throw MaterializationError.invalidFormula(
                    account: entry.name, underlying: "\(error)")
            }
            if let missing = reads.subtracting(known).sorted().first {
                throw MaterializationError.unresolvedReference(
                    account: entry.name, missing: missing)
            }
        }

        var definition = ModelDefinition<Double>(inputs: inputs)
        for entry in derived {
            definition = definition.defining(entry.name, as: entry.formula)
        }

        return MaterializedModel(
            definition: definition,
            rollforwards: plan.rollforwards.map {
                Rollforward(opening: $0.opening, closing: $0.closing, seed: $0.seed)
            },
            periods: plan.periods
        )
    }
}

/// A model built from the part of a plan that resolves, and what was left out.
public struct ResolvableModel: Sendable {

    /// The model, holding every account that could be built.
    public let model: MaterializedModel

    /// The accounts removed, each naming what it could not read.
    public let dropped: [Residue]
}

extension ModelMaterializer {

    /// Builds the part of a plan that resolves, and reports the rest.
    ///
    /// ``build(from:)`` throws on the first hole, which is the right answer when a
    /// caller wants a whole model or nothing. It is the wrong answer when a caller
    /// wants to know *how much* of a workbook works: on the Wharton `ANSWER KEY` a
    /// single exit-year row that cannot be stated as a period rule stops a sheet
    /// whose income statement, cash-flow build and debt schedule are all sound.
    ///
    /// This is refusal, not repair. Nothing is filled in, defaulted, or guessed.
    /// An account naming something the model does not define is **removed** and
    /// returned, along with everything that then read it — a model built on a
    /// dropped account is not a model. What comes back is a definition every part
    /// of which the sheet actually supports.
    ///
    /// - Parameter plan: The recognized plan.
    /// - Returns: The model and the accounts left out of it.
    /// - Throws: ``MaterializationError`` for anything that is not a missing
    ///   reference — a duplicate account, or a formula that will not parse. Those
    ///   are defects in the plan rather than gaps in the sheet, and dropping them
    ///   quietly would hide a bug in recognition.
    public static func buildResolvable(from plan: RecognizedModel) throws -> ResolvableModel {
        var kept = plan.accounts
        var dropped: [Residue] = []

        // Each pass removes exactly one account, so the plan's own size bounds the
        // work. Stated as a ceiling rather than left to a `while true` that relies
        // on the body always finding its way out.
        for _ in 0...plan.accounts.count {
            let openings = Set(plan.rollforwards.map(\.opening))
            let known = Set(kept.map(\.name)).union(openings)
            var offender: (account: RecognizedAccount, missing: String)?

            for account in kept {
                guard let formula = account.formula else { continue }
                let reads: Set<String>
                do {
                    reads = try FormulaEvaluator<Double>.accountNames(in: formula)
                } catch {
                    throw MaterializationError.invalidFormula(
                        account: account.name, underlying: "\(error)")
                }
                if let missing = reads.subtracting(known).sorted().first {
                    offender = (account, missing)
                    break
                }
            }

            guard let offender else { break }
            kept.removeAll { $0.name == offender.account.name }
            dropped.append(
                Residue(
                    label: offender.account.name,
                    cells: offender.account.provenance,
                    reason: .unresolvedReference))
        }

        let resolvable = RecognizedModel(
            periods: plan.periods,
            accounts: kept,
            // A carry whose closing account is gone would leave the driver
            // supplying an opening nothing ever closes.
            rollforwards: plan.rollforwards.filter { carry in
                kept.contains { $0.name == carry.closing }
            },
            residue: plan.residue
        )
        return ResolvableModel(model: try build(from: resolvable), dropped: dropped)
    }
}
