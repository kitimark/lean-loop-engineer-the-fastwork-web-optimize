---
title: Math review of the Fw/Spec declarations (math view vs Lean)
date: 2026-10-17
status: CONFIRMED
---

# Math review of `research/kickoff/05-lean-sketch/Fw/Spec`

The durable record for the "reviewed" chip on the Math view of `docs/plan/loop-plan.html`.

## Review 1: math-reviewer, back-translation, at ea9d6b8

- Method: for every declaration, the reviewer wrote its own math from the Lean with the docstrings stripped, then
  compared it with the docstring's `$$` statement.
- Result: **72 agree, 0 disagree**.
- Declarations per module: Cost 10, Flags 16, Frames 8, Lease 14, Stage 11, Verdict 13 (72; the nested
  `resolve.check` in Flags counts as one).

## Review 2: reviewer-rev5, independent check, at f6d9278

- All 28 theorems, plus the definitions `tick`, `countAbove`, `below`, `verdict`, `Rule.holds`, `Config.ok`,
  `resolve`, `mainUs`, `onTime`, `step`, `Inv` and `gateOk`, were checked symbol by symbol. They agree on
  quantifiers, ≤ vs <, ℕ/ℤ, fold order, `erase` removing the first occurrence, and expiry ≤ now.
- `#print axioms` on the built oleans: only `propext`, `Quot.sound` and `Classical.choice`; no `sorryAx`.
- All 128 TeX fragments on the page parse in KaTeX 0.16.11 (throwOnError, strict), with 0 warnings.
- Wording issues found, with the math right: `Frames.tick_ge5_iff` docstring English (the bucket is ≥ 37.5 ms);
  `Lease.requeue_keeps_place`, `renew_never_shortens` and `release_fifo` leave variables free in the LaTeX instead
  of quantifying them. Both are queued for the Lean owner.

## Not covered

- The verdict false-better rate (1/70 for 4v4, 1/252 for 5v5) has no Lean proof yet. It is planned for M0 as a
  bound, ≤ 1/C(8,4), with equality only when ties have probability 0.
