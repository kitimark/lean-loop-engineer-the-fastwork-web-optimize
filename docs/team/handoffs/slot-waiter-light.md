# slot-waiter-light handoff
State: branch worktree-wf_dc90f414-b1f-1 (see its log for the commit); slot-self tests 7 pass.
Change: `fw slot ...` no longer loads fw.ts. New `apps/runner/src/fw-entry.ts` (package.json `fw` script) dispatches `slot` to new `apps/runner/src/slot-main.ts`, else imports fw.ts. `scripts/slot-self.mjs` waits in-process via slotMain (plan() returns `{slot}` instead of an fw.ts argv). Same "fw slot" span in timing.
Measured (ps rss, process group of a queued waiter): slot-self 168 -> 99 MB (2 -> 1 process); `pnpm -s fw slot run` node part 118 -> 101 MB (pnpm 129 stays).
Follow-ups: waiter is 99 MB vs 46 MB bare node (TS strip cost; a precompiled JS waiter would cut it); `manage-package-manager-versions=false` would drop the pnpm shim's second pnpm; scripts/sim-lock.sh still calls fw.ts directly.
Read first: docs/team/tools/slot.md "Light waiter", scripts/slot-self.mjs.
