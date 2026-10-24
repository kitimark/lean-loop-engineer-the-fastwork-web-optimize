# unthrottle-parts-lean

- Branch `worktree-wf_76be6a23-597-1`, worktree `.claude/worktrees/wf_76be6a23-597-1`; code `bc51e45e7`, note
  `0f799d0b4`, main merged at `242246804`, wiring `4efc468e9`. CI runs: none (no CI in this task).
- Verified: `sh lean/scripts/check.sh` green through `fw slot` (axiom check 0 failing; golden 33 lines up to date);
  `@fw/contracts` test 11/11; `apps/runner` land-inputs 60/60.
- Wired: `import Fw.Device.ThrottleParts` in `lean/Fw.lean`; job "device-throttle-parts golden check" in
  `lean/scripts/check.sh` (lint-check-sh clean).
- Open (lead at land, Trigger.lean outside writes): in `lean/Fw/Ci/Trigger.lean` lean.yml row (line 209) append
  `"packages/contracts/golden/device/throttle-parts.jsonl",` after `".../device/stillruns.jsonl",`; then
  `cd lean && lake test -- --write-ci-trigger-golden` and `node scripts/ci-paths.mjs --write`. Until then
  `node --test scripts/ci-paths.test.mjs` fails 2 tests and plan lint prints one writesClosure error, both this row.
- Files: `lean/Fw/Device/ThrottleParts.lean`, `lean/scripts/ThrottlePartsGolden.lean`,
  `packages/contracts/golden/device/throttle-parts.jsonl`, `research/notes/2026/10-2x-unthrottle-parts.md`,
  `lean/Fw.lean`, `lean/scripts/check.sh`.
- Theorems: `throttled_delay`, `curve_throttled`, `curve_throttled_band`, `hit_throttled`, `curve_lifted`,
  `constant_harmless`, `threaded_same`, `time_same`, `threaded_no_stills`, `time_no_stills`, `mode_*`,
  `unthrottle_no_stills`, `reach_*` (one per branch), `hit_parts`, `namedNotHit_reach`.
- Conventions: shown-value still runs use `StillRuns.runs` on rows `(v, v)`; period `p = throttleK d + 1`; a part's class
  is `reach source shape`, each premise a file:line under `apps/site/src/parts/`.
- Follow-ups: pulse bound for chases (people.card, commission); platform.shrink threaded timeline; morph root lock
  (look change). Measure task `unthrottle-parts-measure` reads golden `kind: "key"` and `kind: "example"` lines.
- Read first: the note, then `ThrottleParts.lean` sections "The model" and "Per-part classification".
