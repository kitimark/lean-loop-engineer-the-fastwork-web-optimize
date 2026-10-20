# Handoff: earn-transition-retarget (lean-prover), round 3 (final design round, split A)

State: branch `worktree-wf_e34eb985-8ed-1`, final commit in the report; CI ref `ci/earn-transition-retarget`.
Land integration (after main merge cbd488d9): commit "trajectory table: rule 201 is-earn-still" adds that rule to Lean `rules`, RULES and the golden; later lines shift by 3.

Read first: `research/notes/2026/10-20-earn-transition-retarget.md` (model, counts, look-change class, review strips),
then `lean/Fw/Parts/NavEarnOpt.lean` and `lean/Fw/Preset/{V2Proved,Gen}.lean` (look-change parts).

Verified:
- `Fw.Parts.NavEarnOpt`: `settled3_same` and `visSame_settled3` over `Settled3`; `#guard settled3B` witnesses frames
  41 to 82 per push and viewport. `valueChanges`: close-push opacity changes go from 20 to 40.
- Look-change class: `part.json` has `kind: proposal, visClass: L`. `Fw.Preset.ok` refuses class L (`look_not_mem`,
  `lookCandidates_not_mem`); `Gen.parsePart` refuses an optimized variant of class L; `Gen.lookDecisions` holds the
  user decision. Golden `packages/contracts/golden/preset/look-change.candidates.jsonl`, TS check `look-change.test.ts`.
- Review strips are not in git. They are CI artifacts of run 39473950464 (`frames-chromium`,
  `frames-playwright-webkit`, path `strips/<engine>-<width>-<push>.png`, expire 2026-11-19); the lead's private review
  page holds a copy. `results/earn-look-review/index.json` names each strip by artifact and path, with shot counts
  and `usable` = min(shots.faithful, shots.flag) >= 10: all Chromium strips, and WebKit only at 390 close.
- Ledger row n 39: status `look-change`, webkit `unknown`, `visual` sums named as sums, `next` and
  `userDecision.review` point at the run's artifacts, `missingWhy` names the 1 to 10 WebKit shots.

Conventions:
- Every user decision on a look change goes in `Gen.lookDecisions`; regenerate with `Fw.Preset.Gen.run []`.
- A frames run is a push to `ci/*` whose head commit message has `[ci:trajectory-probe] [frames:part:variant]`.
- Page renders never enter git; index them by run id, artifact and path.

Open:
- Task earn-look-review-webkit: macOS Playwright WebKit strips (390, 1280, open, close, >= 10 shots per arm and push),
  and the from-to shot labels in `frames.mjs`. The user's visual review stays pending until it delivers.
- Close push: hold `is-earn-still` until the tween ends. WebKit region B paint and composite counters.
