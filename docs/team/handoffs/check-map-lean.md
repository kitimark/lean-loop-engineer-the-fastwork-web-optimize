# check-map-lean (handoff)

State: branch `worktree-wf_3766c904-1ef-2`, work at f4ab441 (main 80bfed2 merged). `land --dry` gives VERDICT dry only with
`--allow` for lean/scripts/CheckMapGolden.lean, lean/scripts/check.sh, scripts/checkmap.mjs, scripts/test-checkmap.mjs
(without them: VERDICT scope).

What it does: every tracked file kind maps to a static check, and only the changed files are checked.
- Lean: `lean/Fw/Ops/CheckMap.lean`. It holds `classify` (path to kind), `checkOf` (kind to check), `plan` (paths to argv
  commands), `verdict`/`runOk` (exit codes to pass/fail). Wire ops are `ops.checkMap` and `ops.checkVerdict` (Fw/Wire.lean).
- Theorems: precommit_covers, tracked_mapped (156 frozen keys, `decide +kernel`), plan_covers/plan_sound,
  cmdsFor_covers/sound, checkOf_exempt_iff, verdict_ok_iff, verdict_strict, runOk_iff. Only standard axioms.
- Golden: packages/contracts/golden/ops/checkmap.jsonl (15 rows) from lean/scripts/CheckMapGolden.lean; checked as a
  `--check` job in lean/scripts/check.sh.
- Runner: scripts/checkmap.mjs lists paths, asks fwcore, runs the argv and asks fwcore for the verdict. It holds no
  decisions. Modes: --staged, default (vs merge-base main), --all (~35 s), --tracked, --paths, --strict.
- Wiring: scripts/hooks/pre-commit runs `--staged` (skipped under FW_LAND_TOKEN); scripts/check.sh wraps the default
  mode (~3 s for 10 files).
- Test: `node scripts/test-checkmap.mjs` (golden replay, plus a throwaway repo where a broken .mjs fails both the check and
  the commit).
- Defect fixed: apps/site/scripts/shell-measure.mjs:112 had a comment that had lost its `//`.

Conventions: exit 127 means the tool is missing, and is skipped unless --strict. .d.ts/.d.mts and .tsx use per-package
tsc (needs node_modules). .ts uses node's stripTypeScriptTypes. YAML is parsed with ruby. Lean modules use lake build;
lean/scripts/*.lean uses `lake env lean`.

Open items:
- Add scripts/check.sh to `fw land` candidate checks (apps/runner/src/land.ts); this was out of scope.
- trackedKeys is frozen at c85c1b6. The live guarantee is `--tracked` plus the pre-commit refusing UNMAPPED files. A new
  extension needs a rule in byExt.
- Checks read the working-tree content of staged files, not the index blob.
- The checker helper was not spawned (no Agent tool); the docstrings were self-checked against the 6-item list.

Read first: lean/Fw/Ops/CheckMap.lean header, scripts/checkmap.mjs header.
