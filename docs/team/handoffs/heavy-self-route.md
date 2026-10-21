# heavy-self-route handoff
State: branch worktree-wf_eb2c023d-67c-1, check.sh green, @fw/runner test 2378 pass.
- `scripts/slot-self.mjs <check|test> -- <cmd>`: not held and not CI -> `fw slot run --kind K -- cmd`; FW_SLOT_HELD, CI or FW_SLOT_SELF=off -> direct. Pure `plan()` exported; tests `scripts/slot-self.test.mjs` (plan table, nested exits at once with child code, bare call writes slot state and child sees FW_SLOT_HELD).
- Package `test` scripts are now `node <rel>/scripts/slot-self.mjs test -- pnpm run test:run`; old body lives in `test:run`. Root `lean:build` routes as kind check (`lean:build:run`). `lean/scripts/check.sh` re-execs through the helper before its heavy-lock line.
- Declared reads: Trigger.lean row (+ triggers.jsonl), LandSpeed.lean checkShReads (+ land-speed.jsonl), land.ts CHECK_SH_READS. node-budget test reads `test:run`.
- build-review.js builder prompt: bare forms replaced by "each heavy command routes itself, one per tool call".
- docs/team/tools/slot.md: new "Self-routing" section.
Open: one-off `lake build <t>`, `lake env lean --run`, `npx vitest` not covered (PreToolUse hook, needs user approval). Anything else reading a package `scripts.test` string must read `test:run`.
Read first: scripts/slot-self.mjs, docs/team/tools/slot.md Self-routing.
