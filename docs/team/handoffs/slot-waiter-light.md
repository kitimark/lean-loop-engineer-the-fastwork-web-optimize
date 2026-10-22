# slot-waiter-light handoff
State: branch worktree-wf_dc90f414-b1f-1 (see its log for the commit); round 2 after the Monitor-line blocker.
Change: `apps/runner/src/fw.ts` is a small entry: `slot` loads only `slot-main.ts`, every other group `import("./fw-main.ts")` (the old fw.ts body, renamed). package.json `fw` unchanged (fw.ts), so the Monitor line and WatchDiff goldens are untouched; fw-entry.ts deleted. `scripts/slot-self.mjs` waits in-process via slotMain.
Measured (ps rss of the waiter's process group, node 24.22.0, one run): slot-self 168 -> 98 MB (2 -> 1 process); typed `pnpm -s fw slot run` node part 118 -> 102 MB, pnpm 129 stays (3 processes with the version-switching shim, lead: 95+105+102).
Write outside the graph list: apps/runner/src/fw-main.ts (new, the renamed body).
Follow-ups: precompiled JS waiter (99 MB vs 46 MB bare); `manage-package-manager-versions=false` for the nested pnpm; scripts/sim-lock.sh still calls fw.ts (works, it just loads the slot branch).
Read first: docs/team/tools/slot.md "Light waiter", apps/runner/src/fw.ts, scripts/slot-self.mjs.
