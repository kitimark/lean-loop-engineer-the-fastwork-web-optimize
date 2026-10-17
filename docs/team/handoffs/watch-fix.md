# watch-fix handoff
State: branch `worktree-agent-afc0d06113af70b3e`, one commit on 342a9fb ("obs: watch-fix ..."). Gates green:
`sh lean/scripts/check.sh` (obs golden 57 cases, 0 failures), `pnpm --filter ./apps/runner test` (85 passed).
`pnpm fw watch` once in the worktree (own fwcore) printed:
`agents active 10 idle 0 parked 9 stalled 1 done 345 | load 14.51 mem normal disk 23GB | simlock free | docker 0 wt 16 ci 20 (0 failed)`
with alerts `agent.stalled page-mathview-2` (a teammate whose transcript ends in an unanswered api-request, 331 min)
and `team.overCap` (20 live: 10 teammate, 9 subagent, 1 workflow).
Done (review findings 1-5, Lean rule first, then collector):
1. `waiting` / `agent.permissionWait` gone; `team.permissionWait` = lead Notification newer than the lead's last tool
   event (`Obs.lead`, from spool/main.jsonl). Theorem `permissionWait_iff`.
2. `Kind` (lead/teammate/subagent/workflow) replaces depth; state `parked` (teammate, nothing in flight, last tool
   SendMessage or TeammateIdle newer than last tool); workflow `done` via `workflowDone` or transcript-only silence
   >= `wfQuietMin` (30). Theorems `state_cases` (exactly one state), `state_*`, `agentAlerts_quiet` (parked/done
   raise no agent alert).
3. `team.overCap` counts live non-lead agents, detail by kind and parent link; `parent` from meta.toolUseId.
4. `wait_not_hang`: Agent/SendMessage in flight with a live child is not toolHang (golden cases both ways).
5. `--until-alert` baseline = last line of health.jsonl (`readLastLog`); gh/docker failure carries the previous
   value (<= 1 h) and marks `system.stale`; ENOENT (not installed) = empty, not stale.
Wire: round trips now go through `getObjVal_mkObj` (TreeMap lemma) instead of whnf, fast (~2.5 s for Obs.lean).
Conventions: collector facts only, no decisions in TS. INFERRED: a teammate's SubagentStop followed by TeammateIdle
is a turn end (collector clears stoppedAt); a Start/tool event after Stop = resume. Kept the old rule that a
transcript-only agent ending on text/StructuredOutput is stopped.
Open: docs/plan/loop-plan.html (math view) still shows the old `waiting` rules: regenerate the math view and send the
changed Health/Obs docstrings to math review. Unrelated pre-existing typecheck error in
apps/runner/test/spawn-guard.test.ts (`kinds`). Parked teammates of a dead lead session stay "parked" until the 24 h
ghost scope drops them. No low findings were listed in a handoff, none fixed.
Read first: lean/Fw/Obs/Health.lean (`state`, `agentAlerts`, `sysAlerts`, `health`), apps/runner/src/watch-collect.ts,
docs/team/tools/watch.md.
