# task-preview handoff

State: branch worktree-wf_dc80218e-a93-3 (see git log). Read first: research/notes/2026/10-18-task-preview.md.

- Lean: lean/Fw/Console/Preview.lean (target, admit, tick, stop, reap, Reach/Inv); wire ops console.preview* in
  lean/Fw/Wire/Console.lean; goldens in packages/contracts/golden/console/console.preview*.jsonl (regen:
  `cd lean && lake env lean --run scripts/OpsGolden.lean`). Wire field is `preview`, not `id` (id is the fwcore message id).
- API glue: apps/console-api/src/preview/{facts,manager,routes,serve-child}.ts; one route registration in app.ts, startup/
  shutdown/tick in main.ts. Tests: apps/console-api/test/preview.test.ts (real server child, stub build hooks).
- Web: apps/console-web/src/TaskDetail.tsx, one line in Plan.tsx `Task`; test/task-detail.test.tsx.
- TS stand-ins to replace by Lean: findHead and facts cache (facts.ts).
- Open: previews live in .fw-console/preview/*, not events.jsonl; residual same-UID curl risk (INFERRED); no end-to-end
  build test on CI (stub hooks only; real build checked by hand).
- Merge note: additive; task-state-truth edits task states, no shared files except app.ts/main.ts (one line each).
