# reap-watch-one-rule handoff (round 3, final design round)
Branch worktree-wf_e07fe309-bfe-1, worktree .claude/worktrees/wf_e07fe309-bfe-1, r3 commit d3b1d32ea + merge of main (see `git log -1`).
CI runs: none (accepted limit).
Rule (lean/Fw/Ops/Reap.lean, branches E and F): pickE = until-loop, tool call ended, >= 60 s, absolute $-free awaited
path (`awaitOk`), no live writer of the same worktree id. pickF = own fw- Simulator (ownSims), simAcquired <= start <=
simIdleSince, simVerdict = shutdown with the slot holders and `legacyHeld` (.local/locks/sim live; missing fact = held).
Action class: `planSel` filters `reapOne` by `autoKinds` (A-D) when `auto` is true. reapTick and reapStopLines send
auto true (E/F never auto-stopped); `fw reap --stop` sends false; --list and the agent.held alert read the full
selection. Theorems: auto_plan_no_loop_sim, planSel_auto, planSel_explicit, held_in_plan (auto false), sim_legacy_kept,
await_unsafe_kept, relative_await_kept, dollar_await_kept.
F stop: stopSelected -> io.simStop -> slot.ts simctlShutdown(udid); never TERM/KILL of launchd_sim.
Goldens: packages/contracts/golden/ops/reap-one.jsonl (29 rows; regenerate: cd lean && lake env lean --run scripts/ReapGolden.lean).
Glue (unproved): callLive := ppid > 1; canonAwait (canonPath only for an absolute $-free path); fw- name filter via simctl;
legacyLive of the main checkout's .local/locks/sim.
Verified: see the report of this round (check.sh, runner tests, dry land).
Open follow-ups: next-killorphan-reap (Next.lean `NEXT <id> killOrphan` advice), reap-ef-auto (log E/F per tick,
exit criterion, inode writer evidence, udid at slot release, F alert).
Read first: Reap.lean E/F section and planSel, docs/team/tools/reap.md "Action class".
