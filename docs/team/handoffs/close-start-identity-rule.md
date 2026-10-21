# close-start-identity-rule

State: branch `worktree-wf_b4f30eab-54a-1`, last commit holds this file.

Done:
- Lean `lean/Fw/Gate/Trajectory.lean` section `CloseIdentity`: the first sample without `is-morphing` after one with it,
  in flight and read at most `startLag` after the change (`idFresh`), passes when `cutM` ≤ m(q), m(r) ≤ `cutM` and red,
  alpha lie within 0.5 of `bgRed`, `bgAlpha` at m(q) (`idCheck`); other samples keep `judgeUnit`. Only nav
  `background-color` (`idOn`, `byMRule`).
- Theorems: `idCheck_css`, `idCheck_some`, `idCheck_late`, `idCheck_t0`, `idBucket_fail_undecided` (never more lenient
  than `byM` on undecided samples), `byMId_keep`, `roundM_above/_below/_tie`, mutations `byMId_early/_late/_stale_target/
  _stale_frame/_wrong_f/_wrong_alpha/_progress`, limits `byMId_half`, `byMId_read_late`.
- Golden `packages/contracts/golden/gate/trajectory.jsonl` (310 lines, ops `byMRule`, `idCheck`, `identity`); TS twin in
  `reduce.mjs`; a test checks `from`/`to`/`cut` against the ported CSS and `logic.ts` (the snapshot is outside the
  package's declared inputs).
- Doc `docs/team/tools/trajectory-probe.md` section "Close start by identity": rule, proofs, mutations, limits, re-reduce.

Verified: `sh lean/scripts/check.sh` green; gate-breakpoints tests, `scripts/ci-paths.test.mjs`, runner typecheck and
`land-inputs` (55/55) pass. Re-reduce of 39448209903, 39452631146, 39466179818, 39456741492, 39472217441 against main: 6 Linux WebKit nav
background units change, all fail to pass. All 421 decided samples pass.

Finding: admission of hero.exit scoped cannot proceed. macOS WebKit close@0 at 390/640 px still fails on later in-flight
samples of passes whose class went at m(q) 133-282; they move from `bgRed m(q)`, the original from near the cut.
Follow-up: judge those samples against the transition from `bgRed m(q)` (nav background curve and duration).

Open: `colourFromV1` (old-kit oklab to sRGB) is TS glue, not checked against Lean.

Read first: the doc section, then `CloseIdentity` from `def idCheck` to `byMId_read_late`.
