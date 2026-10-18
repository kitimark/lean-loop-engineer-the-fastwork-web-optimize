# preset-v2-proved handoff

**State:** branch `worktree-wf_df082d5f-ac9-4` (see `git log -3`), round 2 (final design round) after review; main merged.

**What exists**
- `lean/Fw/Preset/V2Proved.lean` decides the arm. A flag is a member iff all of these hold:
  - it is registered `optimized`;
  - no ledger row with `flag = f` has `fResult = model-bug`;
  - it has a link, and every linked (part, candidate) names exactly one row, with status `proved` and no `model-bug`;
  - it is the first such flag of its part in link order.
  Theorems: `mem_preset_iff`, `falsified_not_mem`, `linked_row_blocks`, `unlinked_not_mem`, `preset_part_unique`, `generate_ok`.
- `lean/Fw/Preset/Gen.lean` holds the link table (INFERRED), the parsers and `run`. `run []` writes
  `packages/contracts/golden/preset/v2-proved{.json,.decisions.jsonl}` and `apps/site/src/registry/presets/v2-proved.json`.
- Gate: the `preset v2-proved check` job in `lean/scripts/check.sh` runs `Fw.Preset.Gen.run ["--check"]`, which regenerates
  the 3 files from `research/findings/ledger.json` and `apps/site/src/parts/*/part.json` and fails on any byte difference.
  Its 3 reads outside `lean/` are declared in `checkShReads` (`Fw.Console.LandSpeed`, golden `console/land-speed.jsonl`)
  and `CHECK_SH_READS` (`apps/runner/src/land.ts`); no exception list was touched.
- `apps/site/src/registry/presets/v2-proved.test.ts` reads only the site: each flag is a registered optimized variant;
  `?preset=v2-proved` resolves and renders.

**Verified:** check.sh green; site vitest 1799/1799; runner land-inputs + land-prelock 46/46. The reviewer's bypass
(morph.countdown swapped to `strip` in all 3 files) fails the check job with exit 1.

**Open items (follow-ups)**
- `?fw=preset:v2-proved` does not resolve (resolve.ts is outside writes); `?preset=v2-proved` does.
- The link table is INFERRED; an explicit `flag` field on ledger rows would make it identity. Row 1 (engine.scroll) is
  proved but no-win, with visual equality open.
- Any ledger or part.json edit now selects check.sh; a ledger edit to a linked row fails it until `run []` is rerun.
- To regenerate from `lean/`: a file with `import Fw.Preset.Gen` and `#eval Fw.Preset.Gen.run []`, then `lake env lean <file>`.
