# review-reports handoff (console-builder)

State: branch worktree-wf_0d8bc841-dda-1, built on main; commits 95461533 (Lean), f86e0d53 (api, CLI), then web + docs.

Done and verified:
- Lean `lean/Fw/Console/Report.lean` + `lean/Fw/Wire/Report.lean` (op console.report), goldens report.jsonl (30 cases).
- console-api `src/review/reports.ts` (GET/POST /api/reports, POST /api/reports/:id/answer), 9 tests.
- runner `reportPostCli` in `src/review.ts`, dispatched in `src/fw.ts`; 4 tests.
- console-web `src/Reports.tsx`, mounted in `ReviewsView`; `test/report.test.tsx` (8 tests); tsc clean.
- `results/review-reports/example.json` (numbers from research/notes/2026/10-2x-smoothness-webkit.md, run 39634194664).
- docs/team/tools/review.md has a Reports section.

Writes outside the graph list: apps/console-api/src/app.ts (mount), apps/runner/src/fw.ts (dispatch), results/review-reports/example.json.

Open:
- The Reviews tab badge counts look-change reviews only; adding `openReports` needs App.tsx (outside this task).
- The strips link in the example is a placeholder (OWNER/REPO).
- The lead posts the first real report; each experiment task posts its own.

Read first: docs/team/tools/review.md (Reports), lean/Fw/Console/Report.lean (theorems).
