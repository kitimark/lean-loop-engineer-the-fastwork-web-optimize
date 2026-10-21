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
  Concretely: A's `ease_err` and `bisect_value_err` take a rational root as a hypothesis, so they say nothing when s*
  is irrational (the usual case); then A's only content is `bracket_cut`. Only B proves the 2^-40 bound for every t
  in (0,1). CONFIRMED.
- **Neither models the engines.** Browsers compute in floating point. So `ℝ` is the curve the CSS spec defines, not
  what WebKit or Chromium computes. INFERRED.
- **Both found the header true.** The midpoint error is in fact 2^-41, and x(s) is strictly monotone even though its
  slope can be 0 at one point (`slope 1 0 (1/2) (1/2) = 0`, a `#guard`). CONFIRMED (`Fw.Parts.Bezier.bisect_value_err`,
  `FwMath.Bezier.bisect_err`, `bx_strictMono`).

## A vs B

| | A: core Lean, `Rat` (`lean/Fw/Parts/Bezier.lean`) | B: Mathlib, `ℝ` (`lean-math/FwMath/Bezier.lean`) |
|---|---|---|
| headline | `bracket_cut`, `ease_err` (every rational root, error ≤ 3·2^-(steps+1)) | `existsUnique_root`: ∃! s* ∈ [0,1], x(s*) = t; `ease_exact` bundles it with abs(bisect − s*) ≤ 2^-40 and abs(ease − y(s*)) ≤ 3·2^-40 (its ∃! is over points meeting all four, so uniqueness of the root itself is `existsUnique_root`) |
| cannot say | that a root exists (it may be irrational) | anything about the floating-point code in browsers |
| reuse | n/a | the bracket lemmas of A, cast to `ℝ` (`bx_cast`, `ease_cast`) |
| theorems / added lines | 28 / +261 | 16 / +188 |
| tactics | `grind` with product hints | `nlinarith`, IVT (`intermediate_value_Icc`), `fun_prop` |
| time to write (estimate, INFERRED) | about 20 min | about 15 min after setup |
| local check | 1.84 s, 496 MB RSS (`lake env lean`) | 17.9 s build from a cleared `.lake/build`, 1.9 GB RSS |
| setup | none | `lake update` 204 s; olean download 52 s (98 MB of archives, unpacked 1.41 GB; 1435 oleans locally because the first, wider import set was fetched; the closure of the final import is 1416 archives, as on CI) |
| CI | runs in lean.yml as today | separate lane `lean-math.yml`: job `math` 78 s cold, 63 s warm (lean.yml job `lean` 104 s on the same push) |

All times and sizes (except the write-time estimates) MEASURED on this Mac (one debug build) or on GitHub Actions (run ids below).
The import set is `Mathlib.Topology.Algebra.Ring.Real` only (`#min_imports`). A wider first set cost 1421 files
against 1416, so pruning imports barely changes the download. MEASURED.

## CI

- Cold run 39563777430 (cache miss): guard 8 s, job `math` 78 s, of which fetch 43 s (dependency clones plus 1416
  olean archives) and `lake build` 7 s; it saved the `mathlib` cache. MEASURED.
- Warm run 39564041178 (cache hit, 1416 archives restored in 1 s): job `math` 63 s, of which fetch 35 s and
  `lake build` 8 s. MEASURED. The fetch is now mostly the git clones of the 8 dependencies. Caching
  `lean-math/.lake/packages` would shorten it, at about 1.4 GB per cache entry. INFERRED (from the step times).
- The lean lane on the cold push (run 39563777420) passed; its job `lean` took 104 s. MEASURED.
- Triggers differ from the task text on purpose: besides `lean-math/**`, the lane also runs on changes to
  `lean/Fw/Parts/Bezier.lean` (FwMath imports it), `lean/lakefile.toml`, `lean/lean-toolchain`, `.node-version` and
  `changed-inputs.mjs`, or on `[ci:lean-math]` in the commit message. fwcore's Trigger table (`Fw.Ci.Trigger`) and the
  two ci goldens gained the lean-math row; lean.yml and the fwcore build do not depend on lean-math. CONFIRMED.

## Recommendation (advice, not a decision)

- Keep the core statements in `Fw` (Mathlib-free, fast, part of every fwcore build).
- Treat `lean-math/` as an optional companion lane for claims that need real analysis (existence of roots, limits).
  It costs a 98 MB download and 1.4 GB on disk per checkout. Its `ci/*` cache is scoped to one branch, so each new
  branch pays the cold run.
- Follow-up: state A over the ordered-field classes that `grind` supports. B could then instantiate it at `ℝ`
  without the casts.
