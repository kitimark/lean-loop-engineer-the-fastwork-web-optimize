# mathlib-poc handoff

State: branch worktree-wf_352c9391-5d5-1, CI branch ci/mathlib-poc. Commits: adda43e0 (A), e2915aa9 (B),
e0747c4f (CI lane), then the note and handoff commit (see `git log`).

Verified:
- A `lean/Fw/Parts/Bezier.lean`: `bx_strictMono`, `bracket_inv`, `bracket_cut`, `ease_err`, with `#guard`s.
  `sh lean/scripts/check.sh` exit 0 (61 s).
- B `lean-math/FwMath/Bezier.lean`: `existsUnique_root` (IVT plus injectivity), `bisect_err`, `ease_err`, and the
  headline `ease_exact`. Local `lake build` 17.9 s.
- `#print axioms` shows only propext, Classical.choice and Quot.sound for both headlines.
- `node --test scripts/ci-paths.test.mjs` 54/54; `apps/runner test/land-inputs.test.ts` 55/55.
- CI lane `lean-math.yml`: see the run ids in research/notes/2026/10-21-mathlib-poc.md.

Conventions:
- `lean-math/` is a separate Lake package (Mathlib v4.35.0 plus `fwcore` by path `../lean`). `lean/` never requires
  Mathlib, and lean.yml inputs do not match `lean-math/**`.
- Mathlib oleans: `lake exe cache get Mathlib.Topology.Algebra.Ring.Real` (it takes module names; file paths fail).
  If an import is added, add its module to that command in `.github/workflows/lean-math.yml`.
- The CI row is `lean-math.yml` in `Fw.Ci.Trigger.table`, with cache writer `("lean-math.yml", "math", "mathlib")`.
  `unseeded_caches` now lists `mathlib`. Regenerate goldens with `cd lean && lake test -- --write-ci-trigger-golden`.
- The `lean-math/FwMath/Bezier.lean` import of `Fw.Parts.Bezier` gives a Lake warning (a non-module file imports a
  module-system Mathlib file). It is harmless.

Open:
- The lead decides whether to keep lean-math/ (the note recommends: optional lane, core stays Mathlib-free).
- The new Bezier theorems still need math review.
- Follow-up: state A generically over ordered fields so that B reuses it without casts.

Read first: research/notes/2026/10-21-mathlib-poc.md, then lean-math/FwMath/Bezier.lean.
