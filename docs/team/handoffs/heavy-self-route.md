# heavy-self-route handoff
State: branch worktree-wf_eb2c023d-67c-1 @ r2 commit 4ff67fa4 (+ this handoff commit), main merged, check.sh green, @fw/runner test 2396 pass, ci-paths 54 pass, slot-self 5 pass.
Round 2: land.ts package reads + Trigger.lean rows (difftest, visual-diff, premise-tests) declare scripts/slot-self.mjs, triggers.jsonl regenerated; build-review.js dry-land forms and --cache check/test forms (no --cache in the helper: cache key has no cwd); slot.md sim-holder FW_SLOT_HELD note.
Follow-ups left: held-slot wait test, check.sh guard test, land pool under one slot, slot timeout reason in land checks.
Writes outside the graph list: land.ts, node-budget.test.ts, Trigger.lean, LandSpeed.lean, triggers.jsonl, land-speed.jsonl, slot-self.test.mjs.
- `scripts/slot-self.mjs <check|test> -- <cmd>`: not held and not CI -> `fw slot run --kind K -- cmd`; FW_SLOT_HELD, CI or FW_SLOT_SELF=off -> direct. Pure `plan()` exported; tests `scripts/slot-self.test.mjs` (plan table, nested exits at once with child code, bare call writes slot state and child sees FW_SLOT_HELD).
- Package `test` scripts are now `node <rel>/scripts/slot-self.mjs test -- pnpm run test:run`; old body lives in `test:run`. Root `lean:build` routes as kind check (`lean:build:run`). `lean/scripts/check.sh` re-execs through the helper before its heavy-lock line.
- Declared reads: Trigger.lean row (+ triggers.jsonl), LandSpeed.lean checkShReads (+ land-speed.jsonl), land.ts CHECK_SH_READS. node-budget test reads `test:run`.
- build-review.js builder prompt: bare forms replaced by "each heavy command routes itself, one per tool call".
Open: one-off `lake build <t>`, `lake env lean --run`, `npx vitest` not covered (needs a user-approved PreToolUse hook). Anything else reading a package `scripts.test` string must read `test:run`.
Read first: scripts/slot-self.mjs, docs/team/tools/slot.md Self-routing.
