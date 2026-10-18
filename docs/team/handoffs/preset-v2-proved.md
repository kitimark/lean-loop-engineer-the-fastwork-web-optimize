# preset-v2-proved handoff

**State:** branch `worktree-wf_df082d5f-ac9-4` (see `git log -3`), pushed as `ci/preset-v2-proved`; chromium-counts
dispatched with `target=rewrite preset=v2-proved runs=1` (run 39131932466).

**What exists**
- `lean/Fw/Preset/V2Proved.lean` decides the arm: a flag is a member iff it is registered `optimized`, no ledger row with
  `flag = f` has `fResult = model-bug`, it has a link, every linked (part, candidate) names exactly one ledger row with
  status `proved` and no `model-bug` fResult, and it is the first such flag of its part in link order
  (`mem_preset_iff`, `falsified_not_mem`, `linked_row_blocks`, `unlinked_not_mem`, `preset_part_unique`, `generate_ok`).
- `lean/Fw/Preset/Gen.lean` holds the link table (flag to ledger rows, INFERRED), the parsers and `run`: it writes
  `packages/contracts/golden/preset/v2-proved{.json,.decisions.jsonl}` and `apps/site/src/registry/presets/v2-proved.json`;
  `run ["--check"]` throws when any differs.
- `apps/site/src/registry/presets/v2-proved.test.ts`: site preset equals golden; ledger inputs the golden recorded equal
  the current ledger; registered optimized flags equal the decided ones; `?preset=v2-proved` resolves and renders.

**Regenerate:** from `lean/`, a file with `import Fw.Preset.Gen` and `#eval Fw.Preset.Gen.run []` (or `["--check"]`), then
`lake env lean <file>`.

**Verified:** check.sh green; site vitest 1803/1803; mutating the site preset fails the Lean check; setting
`fResult: "model-bug"` on a linked row fails both vitest and the Lean check.

**Open items**
- `?fw=preset:v2-proved` does not resolve; `resolve.ts` was outside writes. PLAN syntax `?preset=v2-proved` works.
- The Gen `--check` is not a check.sh job yet (outside writes); vitest is the gate today.
- The ledger has no `flag`/`fResult` fields yet; convention: `flag: "part:variant"`, `fResult` in {pass, unusable,
  model-bug}; any other value makes the generator error.
- nav.hitTest has two proved variants; link order picks `elements-skip` (INFERRED); `hit-skip` is shadowed.
- A ledger edit to a linked row fails the vitest until the preset is regenerated (accepted limit).

**Read first:** the docstrings of `Fw.Preset.preset` and `Fw.Preset.Gen.links`.
