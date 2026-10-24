# unthrottle-parts-lean

- Branch `worktree-wf_76be6a23-597-1`, worktree `.claude/worktrees/wf_76be6a23-597-1`; last code commit `bc51e45e7`, note
  `0f799d0b4`, main merged at `bfdfa4e03`. CI runs: none (no CI in this task).
- Verified: `lake build Fw.Device.ThrottleParts` green; axioms standard (propext, Classical.choice, Quot.sound); golden
  `--check` up to date (33 lines).
- Open: lead wires at land:
  - `lean/Fw.lean`: `import Fw.Device.ThrottleParts`
  - `lean/scripts/check.sh` job line: `job "device-throttle-parts golden check" lake env lean --run scripts/ThrottlePartsGolden.lean --check ../packages/contracts/golden/device/throttle-parts.jsonl  # per-part throttle classification and phone-key predictions unthrottle-parts-measure checks against (Fw.Device.ThrottleParts)`
- Files: `lean/Fw/Device/ThrottleParts.lean`, `lean/scripts/ThrottlePartsGolden.lean`,
  `packages/contracts/golden/device/throttle-parts.jsonl`, `research/notes/2026/10-2x-unthrottle-parts.md`.
- Theorems: `throttled_delay`, `curve_throttled`, `curve_throttled_band`, `hit_throttled`, `curve_lifted`,
  `constant_harmless`, `threaded_same`, `time_same`, `threaded_no_stills`, `time_no_stills`, `mode_*`,
  `unthrottle_no_stills`, `reach_*` (one per branch), `hit_parts`, `namedNotHit_reach`.
- Conventions: shown-value still runs use `StillRuns.runs` on rows `(v, v)`; period `p = throttleK d + 1`; a part's class
  is `reach source shape`, each premise a file:line under `apps/site/src/parts/`.
- Follow-ups: pulse bound for chases (people.card, commission); platform.shrink threaded timeline; morph root lock
  (look change). Measure task `unthrottle-parts-measure` reads golden `kind: "key"` and `kind: "example"` lines.
- Read first: the note, then `ThrottleParts.lean` sections "The model" and "Per-part classification".
