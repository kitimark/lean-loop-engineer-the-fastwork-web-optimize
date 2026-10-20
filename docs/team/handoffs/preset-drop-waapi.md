# preset-drop-waapi handoff

**State:** branch `worktree-wf_b2d9cca1-299-2` (see `git log -2`), one commit on top of main 7c7053de.

**What exists**
- 3 ledger rows in `research/findings/ledger.json` with `flag` and `fResult: model-bug`, `status: refuted`:
  `morph.tween.waapi.falsified`, `morph.tween.waapiScoped.falsified`, `hero.exit.scoped.falsified`. Each has
  `mechanism` (file:line, status words), `evidence` (user report plus local debug repro, CI pending in task
  trajectory-probe), `leanFor`/`leanAgainst` with existing names, `lesson` and `next` (the fix task).
- The ledger `about` names the optional fields `flag`, `fResult` and `evidence`.
- The files `Fw.Preset.Gen.run []` generated: v2-proved has 8 flags without `morph.tween:waapi`, and the decisions give
  `falsified-flag` for the 3 flags.
- `v2-proved.test.ts` checks that every part the preset leaves out resolves to `faithful`.
- No Lean source change: `Fw.Preset.why` (`falsifiedFlag`) and `falsified_not_mem` already decide this.

**Verified:** `lean/scripts/check.sh` green (`v2-proved: up to date, 8 flags`); site test 5474 passed, 4 skipped;
site typecheck; `scripts/ci-paths.test.mjs`; runner `land-inputs` 55/55.

**Open items**
- CI confirmation of the three bugs (task trajectory-probe).
- Fixes: write `data-fw-morph` at each threshold crossing in the waapi driver, and write the exit values inline on each
  reader. In Lean, tie each threshold to the class the CSS reads, and model WebKit's style cache in `Fw.Engine.Restyle`.
- `is-on-dark` is not re-evaluated on morph changes, which makes the logo dark on dark at 390 px in every rewrite arm
  (nav-bug-mechanism, fault 3). This affects no flag, so it has no row here.

**Regenerate** (from `lean/`): a file with `import Fw.Preset.Gen` and `#eval Fw.Preset.Gen.run []`, then
`lake env lean <file>`. Note: `research/notes/2026/10-20-preset-drop-waapi.md`.
