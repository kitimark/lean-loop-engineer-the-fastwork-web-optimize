---
id: 2026-10-21-mathlib-poc
kind: note
title: "Mathlib POC: does proving the Bezier solver over the reals make our proofs more correct?"
status: final
created: 2026-10-21
authors: [agent:lean-prover]
topics: [lean, mathlib, proofs, bezier, ci]
---

# Mathlib POC (2026-10-21)

Question (user): "can we try to do poc for prove them. i just thinking about it may make our prove more correct ?"
Scope: one claim only, the `lean/Fw/Parts/Bezier.lean` header ("exact to 2^-40", "x monotone"), which no theorem
backed before this task. A proves it in core Lean over `Rat`; B proves it with Mathlib over `ℝ`.

## Answer

- **Correctness: no difference.** Both are checked by the same Lean kernel and use only `propext`,
  `Classical.choice` and `Quot.sound` (`#print axioms` on `Fw.Parts.Bezier.ease_err` and
  `FwMath.Bezier.ease_exact`). MEASURED.
- **Fidelity: Mathlib states more.** A `cubic-bezier` root is usually irrational, so over `Rat` A can only state
  "every rational root s" and "points left of the bracket have x < t". B states what the CSS spec means: a unique
  real root s* exists in [0,1], and the code's answer is within 2^-40 of it. CONFIRMED (the statements below).
- **Neither models the engines.** Browsers compute in floating point. So `ℝ` is the curve the CSS spec defines, not
  what WebKit or Chromium computes. INFERRED.
- **Both found the header true.** The midpoint error is in fact 2^-41, and x(s) is strictly monotone even though its
  slope can be 0 at one point (`slope 1 0 (1/2) (1/2) = 0`, a `#guard`). MEASURED.

## A vs B

| | A: core Lean, `Rat` (`lean/Fw/Parts/Bezier.lean`) | B: Mathlib, `ℝ` (`lean-math/FwMath/Bezier.lean`) |
|---|---|---|
| headline | `bracket_cut`, `ease_err` (every rational root, error ≤ 3·2^-(steps+1)) | `ease_exact`: ∃! s* ∈ [0,1], x(s*) = t, abs(bisect − s*) ≤ 2^-40, abs(ease − y(s*)) ≤ 3·2^-40 |
| cannot say | that a root exists (it may be irrational) | anything about the floating-point code in browsers |
| reuse | n/a | the bracket lemmas of A, cast to `ℝ` (`bx_cast`, `ease_cast`) |
| theorems / added lines | 28 / +261 | 16 / +188 |
| tactics | `grind` with product hints | `nlinarith`, IVT (`intermediate_value_Icc`), `fun_prop` |
| time to write | about 20 min | about 15 min after setup |
| local check | 1.84 s, 496 MB RSS (`lake env lean`) | 17.9 s build from a cleared `.lake/build`, 1.9 GB RSS |
| setup | none | `lake update` 204 s; olean download 52 s (98 MB of archives, unpacked 1.41 GB, 1435 oleans of 8624 Mathlib files) |
| CI | runs in lean.yml as today | separate lane `lean-math.yml`: math job 78 s cold (fetch 43 s, build 7 s); warm: see CI |

All times and sizes MEASURED on this Mac (one debug build) or on GitHub Actions (run ids below).
The import set is `Mathlib.Topology.Algebra.Ring.Real` only (`#min_imports`). A wider first set cost 1421 files
against 1416, so pruning imports barely changes the download. MEASURED.

## CI

- Cold run 39563777430 (cache miss): guard 8 s, job `math` 78 s, of which fetch 43 s (dependency clones plus 1416 olean archives) and `lake build` 7 s; it saved the `mathlib` cache. MEASURED.

## Recommendation (advice, not a decision)

- Keep the core statements in `Fw` (Mathlib-free, fast, part of every fwcore build).
- Treat `lean-math/` as an optional companion lane for claims that need real analysis (existence of roots, limits).
  It costs a 98 MB download and 1.4 GB on disk per checkout. Its `ci/*` cache is scoped to one branch, so each new
  branch pays the cold run.
- Follow-up: state A over the ordered-field classes that `grind` supports. B could then instantiate it at `ℝ`
  without the casts.
