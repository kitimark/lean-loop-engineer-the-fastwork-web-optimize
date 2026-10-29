# shipped-preset handoff

- Branch `worktree-wf_b22a9092-874-1`, worktree `.claude/worktrees/wf_b22a9092-874-1`. No CI runs (none needed: no
  CI or phone runs in this task).
- State: Lean rule, goldens, site registry and test committed; check.sh green at fb2934b2e (slot, cached);
  `@fw/site` test 166 files / 8465 tests pass.

## What is verified
- `lean/Fw/Preset/Shipped.lean`: `shipped = v2-proved ++ extras` (first look-accepted flag per free part),
  theorems `preset_sub_shipped`, `shipped_extra_accepted`, `shipped_look_accepted`, `shipped_part_unique`,
  `generate_ok` (requires/conflicts), `blockers*_nil_iff`, `#guard` examples.
- `Gen.lookAccepted` (accepted and review done), `Gen.shipped_extra_decided`; `Gen.run` writes
  `golden/preset/shipped.json`, `shipped.decisions.jsonl`, site `presets/shipped.json`; `entry.presets` added to
  `v2-proved.decisions.jsonl` rows (no other field moved).
- Current shipped = v2-proved (`engine.scroll:unthrottle`, `hero.exit:threaded`); `nav:earn-logical` blocked by
  `gate webkit` (mac morph cell, run 40872462216). Note: `research/notes/2026/10-2x-shipped-preset.md`.

## Outside the graph writes (declared reads)
- `lean/Fw/Console/LandSpeed.lean` (+ regenerated `apps/runner/src/land-reads.gen.ts`,
  `packages/contracts/golden/console/land-speed.jsonl`): `shipped.json` as a check.sh read.
- `lean/Fw/Ops/CheckMap.lean`, `scripts/checkmap.mjs`: `shipped.json` and `Shipped.lean` as preset generator inputs
  (without it the staged pre-commit preset check fails on a missing `shipped.json`).

## Open
- Site default preset unchanged (lead decides). When an accepted L flag passes both gates, `Gen.run` adds it.

## Conventions
- Never hand-edit the shipped files; regenerate: from `lean/`,
  `printf 'import Fw.Preset.Gen\n#eval Fw.Preset.Gen.run []\n' | lake env lean --stdin`.
