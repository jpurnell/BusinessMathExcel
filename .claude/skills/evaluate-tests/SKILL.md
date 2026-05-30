---
name: evaluate-tests
description: Evaluate a test file against the Test Evaluation Framework, scoring quality across 5 dimensions and outputting a structured JSON scorecard.
argument-hint: <path to test file>
---
Evaluate the test file at: $ARGUMENTS

## Process

1. Read the test file provided.
2. Read the Test Evaluation Framework at `./07_LIBRARY/testEvaluationFramework.md` for the full scoring contract.
3. Analyze the test file against all 5 evaluation dimensions:
   - **Appropriateness** (0-100): Does each test validate the public contract correctly?
   - **Golden Path Coverage** (0-100): Are expected valid behaviors comprehensively tested?
   - **Edge Case Coverage** (0-100): Are numerical/statistical boundary conditions tested?
   - **Invalid Input Handling** (0-100): Are malformed/invalid inputs rejected properly?
   - **Security & Robustness** (0-100): Could inputs cause DoS, overflow, instability, or crashes?

4. For each test function, assess:
   - Purpose and appropriateness
   - Golden path coverage gaps
   - Missing edge cases (empty arrays, NaN, Infinity, zero, negative, very large/small values)
   - Missing invalid input tests
   - Security risks (overflow, underflow, division by zero, log(0), non-convergence)
   - Robustness concerns (flakiness, nondeterminism, floating-point fragility, concurrency)

5. Check for anti-patterns:
   - Exact equality (`==`) on Double/Float — must use tolerance
   - `try!` in tests — use `#expect(throws:)` or `try`
   - Unseeded randomness — use `SeededGenerator` or validate invariants only
   - Assertions that only check `!= 0` or `!= nil` without quantitative bounds
   - Duplicate or copy-paste tests — should use `@Test(arguments:)` parameterization
   - Missing NaN/Infinity handling tests
   - Missing empty input tests
   - No time limits on iterative/convergence tests

## Output

Emit the evaluation as **strict JSON** conforming to this schema:

```json
{
  "summary": {
    "overall_quality_score": 0,
    "coverage_score": 0,
    "edge_case_score": 0,
    "invalid_input_score": 0,
    "security_score": 0,
    "systemic_risks": [],
    "high_priority_gaps": []
  },
  "per_test_analysis": [
    {
      "test_name": "",
      "purpose_inferred": "",
      "appropriateness": { "is_appropriate": true, "issues": [], "suggested_improvements": [] },
      "golden_path_coverage": { "covers_expected_behavior": true, "missing_cases": [] },
      "edge_case_coverage": { "covers_edge_cases": false, "missing_edge_cases": [] },
      "invalid_input_handling": { "tests_invalid_inputs": false, "missing_invalid_inputs": [] },
      "security_analysis": { "has_security_risk": false, "risk_type": [], "details": [], "recommendations": [] },
      "robustness": { "flaky_risk": false, "nondeterminism_risk": false, "floating_point_fragility": false, "concurrency_risk": false, "notes": [] }
    }
  ],
  "missing_global_tests": {
    "statistical_correctness": [],
    "numerical_stability": [],
    "large_scale_performance": [],
    "degenerate_inputs": [],
    "randomized_property_tests": [],
    "fuzzing_opportunities": [],
    "cross_validation_tests": [],
    "regression_tests_needed": []
  },
  "systematic_improvement_actions": [
    { "category": "", "action": "", "priority": "high|medium|low", "can_be_auto_generated": true }
  ]
}
```

## Score Interpretation

| Score | Meaning |
|-------|---------|
| 90-100 | Production-grade |
| 75-89 | Good, minor gaps |
| 50-74 | Moderate weaknesses |
| 25-49 | Significant gaps |
| 0-24 | High risk |

## Rules

- Use the JSON schema strictly — no extra fields, no missing fields.
- Be objective — scores must reflect actual coverage, not intent.
- Prioritize: security risks and invalid input gaps are HIGH priority.
- Every recommended action must be concrete and automatable where possible.
- After outputting JSON, provide a brief plain-text summary with the top 3 actions to take.
