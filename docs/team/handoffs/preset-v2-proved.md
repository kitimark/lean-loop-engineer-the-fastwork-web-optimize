# preset-v2-proved handoff

**State:** branch `worktree-wf_df082d5f-ac9-4` (see `git log -3`), pushed as `ci/preset-v2-proved`; chromium-counts
dispatched with `target=rewrite preset=v2-proved runs=1` (run 39131932466, queued at handoff).

**What exists**
- `lean/Fw/Preset/V2Proved.lean` decides the arm. A flag is a member iff all of these hold:
  - it is registered `optimized`;
  - no ledger row with `flag = f` has `fResult = model-bug`;
  - it has a link, and every linked (part, candidate) names exactly one row, with status `proved` and no `model-bug`;
  - it is the first such flag of its part in link order.
  Theorems: `mem_preset_iff`, `falsified_not_mem`, `linked_row_blocks`, `unlinked_not_mem`, `preset_part_unique`, `generate_ok`.
- `lean/Fw/Preset/Gen.lean` holds the link table (INFERRED), the parsers and `run`. `run` writes
  `packages/contracts/golden/preset/v2-proved{.json,.decisions.jsonl}` and `apps/site/src/registry/presets/v2-proved.json`;
  `run ["--check"]` throws on any difference. To run it from `lean/`: a file with `import Fw.Preset.Gen` and
  `#eval Fw.Preset.Gen.run []`, then `lake env lean <file>`.
- `apps/site/src/registry/presets/v2-proved.test.ts`: site preset = golden byte for byte; recorded ledger inputs = current
  ledger; registered optimized flags = decided ones; `?preset=v2-proved` resolves and renders.

**Verified:** check.sh green; site vitest 1803/1803. Editing the site preset fails the Lean check; `fResult: "model-bug"`
on a linked row fails both checks.

**Open items**
- Dry land refuses with `VERDICT reads`: the static scan in `apps/runner/test/land-inputs.test.ts` flags Gen.lean's 3 path
  literals, though check.sh never runs `run`. Lead's fix: add them to `NOT_REACHED_BY_CHECK_SH`, or wire `--check` into
  check.sh and add them to `CHECK_SH_READS`.
- `?fw=preset:v2-proved` does not resolve (resolve.ts was outside writes); `?preset=v2-proved` does.
- The ledger has no `flag`/`fResult` fields yet. Convention: `flag: "part:variant"`, `fResult` in {pass, unusable, model-bug}.
- nav.hitTest: the link order picks `elements-skip` and shadows `hit-skip` (INFERRED); a ledger edit to a linked row fails
  vitest until the preset is regenerated (accepted limit).
