# Handoff: waapi-tail-webkit-p2 (measure-engineer)

Branch `worktree-wf_b4f30eab-54a-2`, CI branch `ci/waapi-tail-webkit-p2`. Read first: the last section of
`research/notes/2026/10-21-waapi-tail-webkit.md`, then `lean/Fw/Parts/MorphTweenWebkit.lean`.

## State
- Three push-triggered macOS WebKit 1280 recorder runs on separate jobs: 39571243779, 39572308204, 39573516482; phase 1
  run 39527354981 is an extra point. Runs 2 and 3 started the mac leg through `apple_run`.
- Split class c0 in 30 of 30 reps; no C1/C2/C3/C-probe; C4 in 9 of 30, both arms. Cand jumped 15 of 15, base held 15 of 15.
- C-probe ruled out (no read row between the writes). Verdict in Lean (`verdict`, `drop_on_measured`): drop the base
  window on macOS WebKit 1280. The code change is not made.
- The macOS-leg rule of a push is in Lean (`Fw.Ci.Trigger.appleRuns`, `triggers.jsonl`, node twin; the workflow reads `apple_run`).
- Phase 1 review lows fixed in the note: driver line cites, path S (settleFlight), corrected "raf row" rule.

## Verified
`sh lean/scripts/check.sh` green; gate-breakpoints `pnpm test` 543 pass; trajectory-line test 5; `scripts/ci-paths.test.mjs` 54
and `ci-paths.mjs --check` ok; apps/runner `pnpm test` 1750 pass (read `packages/contracts/golden/parts/**` declared in `land.ts`).

## Open
- `waapi-tail-drop`: gate or remove the window on WebKit. No run with the window off exists.
- One engine (Playwright WebKit, macos-26), one width (1280). Stand-ins: recorder and probe plumbing, `normalizeRow` rounding.

## Conventions
- Golden `morph-tween-webkit-rows.jsonl` is written by `goldenText` from `morph-tween-webkit-rows.cases.json` (scratch
  `lake env lean --run`); a `#guard` checks it. Never hand-edit the jsonl.
- A run is one empty commit with the two-line message, `git branch -f ci/waapi-tail-webkit-p2 HEAD`, plain push; no push while a run is pending.
- Writes beyond the graph writes: `lean/Fw.lean`, `MorphTweenWebkit.lean`, `golden/parts/morph-tween-webkit-rows.*`,
  `.github/scripts/trajectory-line.*`, `gate-breakpoints/test/webkit-rows.test.mjs`, `apps/runner/src/land.ts`, `docs/team/tools/trajectory-probe.md`.
