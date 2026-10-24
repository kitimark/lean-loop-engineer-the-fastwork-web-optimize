# reap-watch-one-rule handoff (round 2)
Branch worktree-wf_e07fe309-bfe-1, worktree .claude/worktrees/wf_e07fe309-bfe-1, commit: see `git log -1` (r2 work fa6225adb + merge of main). No CI runs (accepted limit).
Verified: lean/scripts/check.sh green; apps/runner test (tsc + vitest, 3315) green; ci-paths test green; fwcore rebuilt for the goldens.
Rule (lean/Fw/Ops/Reap.lean "Branches E and F"): pickE = until-loop, tool call ended, >= 60 s, no live writer (canonical paths).
pickF = own fw- Simulator (ownSims identity list) with simAcquired <= start <= simIdleSince and Fw.Sup.Adapt.simAction = shutdown (simVerdict).
Stop of F: stopSelected -> io.simStop -> slot.ts simctlShutdown(udid); never TERM/KILL of launchd_sim.
Watch: agent.held for loops only from ops.reapHeld (watch-reap.ts); nextAlerts no longer raises agent.held.
Slot state.json now keeps simAcquired (earliest since of the released sim holders). Goldens: packages/contracts/golden/ops/reap-one.jsonl (23 rows, regenerate: cd lean && lake env lean --run scripts/ReapGolden.lean).
TS stand-ins: none for decisions. Unproved glue: callLive := ppid > 1; canonPath (realpath of dirname); the fw- name filter via simctl.
Open: Fw.Obs.Next killOrphan (Next.lean) is kept as lead advice (`NEXT <id> killOrphan`), not an alert; dropping it touches Wire/Obs goldens and ~15 theorems (follow-up).
Read first: Reap.lean E/F section, docs/team/tools/reap.md E/F.
