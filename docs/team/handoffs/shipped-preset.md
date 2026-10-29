# shipped-preset handoff

- Branch `worktree-wf_b22a9092-874-1`, worktree `.claude/worktrees/wf_b22a9092-874-1`. No CI or phone runs.
- State: committed, main merged at 87d9aa372 (main 8996544df, plan r585); check.sh green there (slot; axiom
  check 0 failing); `@fw/runner` 118 / 3704 rerun there; `@fw/site` 166 / 8465 and `@fw/contracts` 11 at b8fda182f
  (the later merge only moved work-graph.json); ci-paths 56 pass; plan lint 0 errors.
- test-checkmap rerun (slot): every case passes but the Gen-closure case, which fails on main 8996544df too
  (31 modules, 28 missing, same section run against main's checkout).

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
- `lean/Fw/Ops/CheckMap.lean`, `scripts/checkmap.mjs`, `scripts/test-checkmap.mjs` (fixture): `shipped.json` and
  `Shipped.lean` as preset generator inputs (without them the staged preset check misses `shipped.json`).
- `apps/runner/src/land.ts`: apps/site reads add the two shipped goldens `shipped.test.ts` reads.

## Open
- `scripts/test-checkmap.mjs` case "all N modules of Gen's import closure are inputs" fails on main too: Gen imports
  `Fw.Parts.*` and Trajectory imports `Fw.Ci.Pool.Caps`, which `CheckMap.presetInputKey` does not list.
- Site default preset unchanged (lead decides). When an accepted L flag passes both gates, `Gen.run` adds it.

## Conventions
- Never hand-edit the shipped files; regenerate from `lean/`: `printf 'import Fw.Preset.Gen\n#eval Fw.Preset.Gen.run []\n' | lake env lean --stdin`.
