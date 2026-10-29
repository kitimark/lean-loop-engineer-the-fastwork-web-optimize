# gen-merge-retry-bound handoff

- Branch: worktree-wf_52e0813b-89d-1
- Worktree: .claude/worktrees/wf_52e0813b-89d-1
- Last sha: see `git log -1` on the branch (the commit that adds this file).
- CI runs: none (the rows of runs 40668662980, 40671695274, 40674554372 were re-recorded from their downloaded artifacts).
- Verified: check.sh green (axioms standard), gate-breakpoints 830 tests, contracts, site 8453 tests, runner land-inputs,
  scripts/ci-paths.test.mjs, all through fw slot.
- Open: none in the unit. Writes outside the named files: lean/Fw/Gate/Trajectory.lean, lean/Fw/Preset/V2Proved.lean,
  packages/contracts/golden/preset/reader-files.json, packages/gate-breakpoints/test/reader-files.test.mjs,
  apps/runner/src/land.ts (gate-breakpoints read of reader-files.json).

State:
- Rule in lean/Fw/Preset/V2Proved.lean section "Superseded rows": `supersede` (reader change, else retry of a
  no-verdict within `retryBound = 2`), `live`, `keyOutcome` (conjunction of live rows), `tcell` on them.
- lean/Fw/Preset/Gen.lean: `merge` replaces only the row of the same run, engine and walk (`merge_keeps`,
  `merge_idem`); `parseRunId` is strict; `readerOf` hashes the `git ls-tree --full-tree` listing of `readerFiles` at
  the row's commit; `record` fills empty readers of old rows; `run` writes the stored file and refuses empty readers.
- hero.exit:threaded: mac morph no-verdict 40671695274 superseded (retry) by the pass of 40674554372, same reader
  03b75d1b69fa; every cell pass, gate met, only blocker `proofs`.

Conventions:
- Never edit v2-proved.trajectory.jsonl by hand: `Gen.record` then `Gen.run []` from lean/ (usage in
  docs/team/tools/trajectory-probe.md). If a reader file is added, update `Gen.readerFiles`; the reader-files test fails
  until then.

Read first: research/notes/2026/10-2x-gen-merge-retry-bound.md, then the "Superseded rows" section of V2Proved.lean.
