# Cover message — short version (post-merge)

For pasting into email, Slack, or a GitHub comment.

> **Note:** Replaces the earlier cover message from earlier today.
> Receiving v5 of the tech req resolved most of the questions; this
> version surfaces only the one item still needing your call.

---

## Email-length

**Subject:** Quick heads-up on the Swift coherence algorithm port — one question

Hey Devon,

We're porting the HRV coherence algorithm into a Swift package
(`BioFeedbackKit`) that will be the math/signal core for the upcoming
Swift-native narbis Edge app. v5 of the tech req cleared up almost
everything — we're treating §6.3 as canonical and our internal plan is
locked. Wanted to give you a heads-up on the shape of what's coming
and ask one user-impact question.

Full doc:
`project/plans/QUESTIONS/2026-04-08_Coherence_Algorithm_Questions.md`

**The shape:** three coherence algorithm variants behind one
`HRVAlgorithm` protocol so the app can pick at runtime.

1. **`CoherenceAlgorithmCubic`** (default) — exact v5 §6.3, except we
   keep our cubic-spline resample (Kubios standard, ~10× more accurate
   in HF on validated sine fixtures, free on iOS via Accelerate)
2. **`CoherenceAlgorithmLinear`** — exact v5 §6.3 to the letter,
   linear resample. So we have a clean A/B against the cubic version.
3. **`LegacyCoherenceAlgorithm`** — faithful Swift port of
   `hrv_engine.dart` (single-bin numerator, frequency bonus, EMA, the
   whole thing). For continuity for users already trained against
   the Flutter app.

Our read on the Dart engine: the single-bin numerator and the
`0.7×ratio + 0.3×bonus` formula don't match v5 §6.3 and look like
shortcuts a previous developer took rather than deliberate calibration.
We're treating v5 as authoritative.

**The one question:**

Are there existing users with training history built up against the
shipping Dart engine whose scores we'd materially disrupt by switching
them to the v5 algorithm? The Dart engine systematically produces
*higher* scores than v5 because the single-bin numerator and the
+0.30 frequency bonus inflate things. A "85% session" on Dart could
read "62%" under v5 — same physiology, more correct math, but
emotionally feels like a regression to a user using the score as a
personal benchmark.

- If **yes** — we'll default existing users (anyone with non-empty
  session history) to legacy mode and offer an opt-in switch to v5
- If **no** — we'll default everyone to v5-cubic and the legacy mode
  is a debug/comparison tool only

Either way, we can also generate a translation table between the
scales so existing users can mentally calibrate their old scores
against the new ones. Easy once both Swift impls are running against
the same RR fixtures.

Thanks!

---

## Slack-length

Heads-up on the Swift coherence port — v5 cleared up almost everything,
we're treating §6.3 as canonical, and the internal plan is locked.
Three variants behind one protocol so the app picks at runtime:

- **Cubic v5** (default) — exact v5 except we keep cubic-spline
  resample (~10× more accurate in HF, free on iOS)
- **Linear v5** — exact v5 to the letter, for A/B comparison
- **Legacy** — faithful port of `hrv_engine.dart` for continuity for
  existing Flutter-app users

Our read: the Dart engine's single-bin numerator and `0.7×ratio + 0.3×bonus`
formula look like a previous dev taking shortcuts, not deliberate
calibration. We're treating v5 as authoritative.

**One question:** are there users with real training history on the Dart
engine whose scores we'd disrupt by switching them to v5? The Dart
version produces systematically higher scores (an old "85" could read
"62" on v5 for the same physiology — more correct, but feels like a
regression to a benchmark-watching user).

- **Yes** → existing users default to legacy mode, opt in to v5
- **No** → everyone defaults to v5-cubic, legacy is debug-only

Full doc:
`project/plans/QUESTIONS/2026-04-08_Coherence_Algorithm_Questions.md`
