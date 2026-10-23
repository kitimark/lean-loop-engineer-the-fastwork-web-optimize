# writes-closure-doc-touchups

- Branch: worktree-wf_82824cd6-a4b-1 (worktree .claude/worktrees/wf_82824cd6-a4b-1)
- Commits: c9399478f (work), 30c111dad (generator moved into ci-paths.mjs), ba946f773 (main merged)
- Dry land: `VERDICT dry writes-closure-doc-touchups`; review gate: `VERDICT review-ready ... review`
- CI runs: none (all checks are local: check.sh, vitest, node tests)
- Verified: check.sh green; runner 3178/3178 and tsc ok; contracts 11/11; ci-paths 56/56;
  `node scripts/ci-paths.mjs --check` and `--plan-time --check` ok; `fw plan lint` on main's graph: 0 errors
- Open: none inside the graph row's writes.

## What changed
- (1) `docs/team/tools/plan.md` Time section is generated between the `plan-time begin/end` markers by
  `node scripts/ci-paths.mjs --plan-time`. The samples sit in the same block (`jsonl`: exit-0 `fw`
  `plan sync` spans, `closure` = commit contains 9a09d8066); `--refresh <timings.jsonl>` rebuilds them from a local
  timings file, `--check` refuses a stale doc. Table text is Lean `timeTable` (Fw.Obs.Timing p50/p90/maxL/lastN); the
  JS twin replays the golden `timeTable` rows and a test asserts the doc equals `planTimeRender(doc)`.
- (2) Golden `agree` rows: 50 rowGlob-valid globs (`**`, `***`, `**/`, `***/`, `*`, `**/*` and prefixes of six
  patterns), alone and as `["**", "!g"]`, with their hits over `agreePaths`; the test replays them through
  changed-inputs `matches`. Limit stated in plan.md: line terminators in paths (JS `.` vs Lean `**`).
- (3) Lean `readPath` (none on a `..` segment) with `readPath_dotdot`, `readPath_plain`, `dotdot_gap`; `scriptReads`
  uses it; JS twin `readPath` in ci-paths.mjs `gapsFrom`. No lean/scripts/*.sh read had a `..` segment.

## Read first
`lean/Fw/Plan/WritesClosure.lean` `readPath`, `agreeLists`, `timeTable`; then ci-paths.mjs `planTimeBlock`.
