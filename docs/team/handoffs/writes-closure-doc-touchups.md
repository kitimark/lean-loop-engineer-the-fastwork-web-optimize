# writes-closure-doc-touchups

- Branch: worktree-wf_82824cd6-a4b-1 (worktree .claude/worktrees/wf_82824cd6-a4b-1)
- Last code commit: c9399478f, main merged at 0fa410576
- CI runs: none (all checks are local: check.sh, vitest, node tests)
- Verified: plan-closure.test.ts 198/198 before the merge; ci-paths 56/56; `node scripts/ci-paths.mjs --check` ok;
  `node scripts/plan-time.mjs --check` ok; `fw plan lint` on main's graph: 0 errors
- Open: writes outside the graph row: `scripts/plan-time.mjs` (new), `results/plan-sync-time/samples.jsonl` (new).

## What changed
- (1) `docs/team/tools/plan.md` Time section is generated between `plan-time begin/end` markers by
  `node scripts/plan-time.mjs` from `results/plan-sync-time/samples.jsonl` (exit-0 `fw` `plan sync` spans; `closure`
  = commit contains 9a09d8066). `--refresh <timings.jsonl>` rebuilds the samples from a local timings file; `--check`
  refuses a stale doc. Table text is Lean `timeTable` (Fw.Obs.Timing p50/p90/maxL/lastN); the JS twin replays the
  golden `timeTable` rows, and a test asserts the doc equals `render(root)`.
- (2) Golden `agree` rows: 50 rowGlob-valid globs (`**`, `***`, `**/`, `***/`, `*`, `**/*` and prefixes of six
  patterns), alone and as `["**", "!g"]`, with their hits over `agreePaths`; the test replays them through
  changed-inputs `matches`. Limit stated in plan.md: line terminators in paths (JS `.` vs Lean `**`).
- (3) Lean `readPath` (none on a `..` segment) with `readPath_dotdot`, `readPath_plain`, `dotdot_gap`; `scriptReads`
  uses it; JS twin `readPath` in ci-paths.mjs `gapsFrom`. No lean/scripts/*.sh read had a `..` segment.

## Read first
`lean/Fw/Plan/WritesClosure.lean` `readPath`, `agreeLists`, `timeTable`; then `scripts/plan-time.mjs`.
