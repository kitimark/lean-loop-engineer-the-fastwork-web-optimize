# ci-run-dedup handoff
- Branch: worktree-wf_e99eb6af-be6-1; CI branch ci/ci-run-dedup.
- Worktree: .claude/worktrees/wf_e99eb6af-be6-1
- Last pushed commit: 84409c951 (merge of main on top of 1edaf2819).
- CI runs of that push: lean 40210501188 complete, success -> pass; the other workflows of the push are not used as evidence.

## State
- Lean `lean/Fw/Ci/Dispatch.lean`, section "One row per run": `Listed` (run + `updatedAt` ms), `keepNewest`, `dedupById`
  (newest `updatedAt` per id, place of the first row, tie keeps the first), `dupIds`, `OneRunPerId`.
- Theorems: `dedupById_nodup`, `mem_dedupById`, `dedupById_newest`, `dedupById_of_nodup`, `mem_dupIds`,
  `select_dedupById_nodup`, `mem_select_dedupById`, `selectOne_dedupById_found`, `selectOne_dedupById_twice` ([a,a]),
  `selectOne_dedupById_ambiguous` (id set = ids of the wanted rows), `selectOne_dedupById_ambiguous_same` (same rows in
  any order or with copies: ambiguous again, same id set). No `selectOne_dup` reorder theorem: it is false (check.md item 8).
- Golden: `dedup` lines in packages/contracts/golden/ci/dispatch.jsonl (`lake test -- --write-ci-trigger-golden`).
- TS: `dedupById`, `dupIds` in packages/gh-budget/src/want.ts; poller.ts dedups each list before writing the runs-status
  file and appends `{duplicateIds, listed, pagesRead, at}` to the state dir's incidents.jsonl when a tick lists an id twice.
  The `listed` event keeps gh's raw row count (page-cut detection). test/dedup.test.ts replays the golden and the incident.

## Verified
- `lake env lean Fw/Ci/Dispatch.lean` clean; `lake test` golden write + "62 cases ok"; dedup + want tests pass (13).
- CI lean 40210501188 pass; scripts/ci-paths.test.mjs 56 pass; apps/runner land-inputs (vitest) 73 pass.

## Open
- Page-shift cause stays INFERRED until incidents.jsonl shows a `duplicateIds` line.
- Refiling nav:clip-box from run 40196217959: lead.
- docs/team/tools/ts-stand-ins.md not updated (outside writes); want.ts dedup is golden-checked.
