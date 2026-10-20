# Handoff: trajectory-probe (round 2)

State: branch worktree-wf_b2d9cca1-299-1, CI branch ci/trajectory-probe. Measured code = f19913eb (+ e85d995e summary split).
Round 2 is delivered except bug B, which the probe did not witness (open item 1). Results: research/notes/2026/10-21-trajectory-probe.md.

Verified (CI run ids in the note): arm identity on every arm of 6 runs; bug A (WebKit only, Linux 228 and macos-26 187 new
units); bug C is baseline red (never new); coverage and the baseline relation per unit; read timing (reads do not dominate).
Local: gate-breakpoints tests 265, ci-paths 41, apps/runner 1442, `sh lean/scripts/check.sh` green at the last commit.

Conventions
- Lean decides (lean/Fw/Gate/Trajectory.lean); reduce.mjs is the twin, checked against packages/contracts/golden/gate/trajectory.jsonl
  (regenerate: `cd lean && lake env lean --run scripts/TrajectoryGolden.lean`, never by hand). The golden `cases` are two
  constants (init-cost bound 10000).
- Dispatch: `pnpm -s fw run --trajectory --ref ci/trajectory-probe [--fw ..|--preset ..]`, one at a time per sha. Push first, wait
  a minute before dispatching (the push run is skipped by the guard and can be mistaken for the dispatch: use `fw ci wait <runId>`).
- The Apple job runs only on a dispatch with a search (`--fw`/`--preset`) and engines including playwright-webkit.
- Re-reduce artifacts offline: `node packages/gate-breakpoints/src/trajectory/cli.mjs summary --out <dir> --engine <e>`.

Open items
1. Bug B not witnessed (waapi: 0 new nav/logo units in Chromium). Record `document.getAnimations().length` per push sample; try a
   touch drag; compare with the user's repro.
2. Linux WebKit cannot cover the morph push (150 ms frames); use macos-26 for morph too (extend the Apple job to `--paths hero,morph`).
3. Faithful rewrite is baseline red in 57 hero units on macos-26 (mid/hold/b25 rects): investigate.
4. A default-vs-default run is RED from one empty coverage bucket; consider reps 5 or deciding coverage per bucket across reps.
5. Not run: `--reads lean` (not needed). Not wired to the gate or the preset generator (by task).

Read first: docs/team/tools/trajectory-probe.md, then the note.
