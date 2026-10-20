# Handoff: cmr-margin-typed-om

Branch `worktree-wf_e76ba321-3f4-2` (CI refs `ci/cmr-margin-typed-om`, `-b`, `-c`, all at the premise commit 2539f31e).
Read first: `research/notes/2026/10-20-cmr-margin-typed-om.md` (verdict table, read paths with file:line).

## State
- Premise `cv.margin-typed-om` ($p_{33}$): page `packages/premise-tests/pages/cv.margin-typed-om.html`, test `prem.cv.margin-typed-om`
  (`packages/premise-tests/src/tests.mjs`), Lean entry at the end of `registry` in `lean/Fw/Ops/Premise.lean`
  (theorems `planned:cmr-margin-rect-rule`), golden `packages/contracts/golden/ops/premise.jsonl` regenerated.
- Verdict: holds, MEASURED, all 36 cells per engine (normal, skipped cv, scale(0.916667) ancestor x auto, percent, px x four keys),
  Chromium 156.0.8078.4 and Playwright WebKit 27.2 (the premise-tests lane, not the iOS Simulator), 3 runs:
  39354607925, 39354637553, 39354644363. Nothing refuted.
- The Typed OM read leaves the skipped subtree skipped and returns the specified kind; `getComputedStyle` returns the used
  `150px` (finding `premise.cv.auto-margin`, unchanged). The Typed OM gives auto-ness, not the used px.

## Verified
- `lean/scripts/check.sh` green; premise-tests 3/3; apps/runner 1382/1382 (tsc + vitest); `scripts/ci-paths.test.mjs` 41/41;
  `scripts/circleci.test.mjs` 45/45 (no fixture change); packages/contracts 7/7.
- Run 39354644363 is red only for `clock.raf-timeline` (WebKit, 2 ms) and the acked `anim.list`; both outside this task.

## Open
- `fw ci wait` stops with `tooBig` (shared poller, a stale watched run id 1000000000838323 with an 11-page list); `fw ci budget --resume`
  does not clear it. I read the runs with one `gh run list` after a sleep and `gh run download`. The lead may want to clear it.
- Not measured: skipped + scaled together in one cell; the iOS Simulator WebKit.framework.
- Chromium citation in the task text (`computed_style_property_map.cc:129-130`) is `GetCustomProperty`; the built-in path is 118-119.

## Conventions
- The CI push was the allowed form (`git branch -f ci/<n> HEAD`, then `git push origin ci/<n>`); the head commit carries the lane token.
- No write outside the task's files; `docs/team/work-graph.json` untouched.
