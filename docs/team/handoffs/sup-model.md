# sup-model (lean-prover) handoff
State: branch worktree-wf_f48889d4-126-3 (base main bea13736); round 2 commits after efcc5489, last "sup-model r2: findings fixed, handoff". `lean/Fw.lean` imports `Fw.Sup.Props`.
What exists
- `lean/Fw/Sup/Core.lean`: the supervisor model. State (res, leases, pending, tickets, obs), `step c s e : State × List Cmd`, `run`, `Ex.*` fixtures, `#guard`s on every decision function (charge, fitsB, holdOf, span, recent, insertReq, alive, crash, exits, byRank, idle, cands, shedPick, evictPick, shedOn, authed, svcOk, validLease, nubRes, nubLease, killG, footOf) and on whole runs.
- `lean/Fw/Sup/Props.lean` (290 theorems, no sorry/axiom, 0 warnings). Invariant: init_inv, step_inv, run_inv, restart_inv (Inv after a restart from any state), run_eq_fold, sup_auth.
- Identity and processes: owner_unique, spawned_recorded/spawned_sets, adopt_live, step_restart, recover_adopt_or_reap (adopted starts get a probe and a fresh start time), signal_identity (member KILLs only for rows started no earlier than the leader of an absent record's group), stop_never_leased (pre-state: a leased resource is signalled only when the same tick revokes the lease, or the event releases it, drops its owner or restarts), kill_member_unleased, stop_escalates, start_bounded (also refuses the waiters), idle_stopped, stop_only_idle, evict_for_pending (converse), evict_live (liveness: a non-blocked queue prefix lets a non-fitting request TERM its rank-order prefix), exit_releases.
- Leases and budget: grant_ready, admit_fits, spawn_fits, restart_bounded, crash_cap, overrun_sheds (+ shedPick_spec: minimal rank-order prefix, all candidates at warn), starvation_limit, drain_quiet, drain_exit, expired_revoked, client_gone_releases, client_missing_releases (tick variant), nested_no_wait, lease_span.
- Queue and replies: fifo_no_overtake, aged_granted_by, ticket_age, reply_once, reply_by_deadline. Section "The hypotheses are met" gives a non-vacuity `example` for each headline theorem on `Ex.after` runs.
Stated limits (judge against these)
- owner_unique is model-internal; the OS side rests on S1, S2 and the audit record (auditRec). run_eq_fold is evidence only with the runtime golden replay against fwcore.
- restart_bounded is a per-spawn gate on the recent crash count, not a trace bound; crash_cap fails the record for the window.
- starvation_limit: while shedding, only nested zero-cost joins are granted; a long shed starves the queue until reply_by_deadline refuses it.
- Fairness is one step (aged_granted_by + fifo_no_overtake + reply_by_deadline). ACCEPTED LIMIT (lead, r2 review): the (1+Ψ)·holdMax trace bound is not proved and needs a design change, task sup-fairness (keep the ticket on a deadline refusal, or make svc grants respect a blocked job). The starvation mechanism (a svc grant on a ready resource overtaking a blocked older job) is INFERRED: the example after aged_granted_by uses Ex.cfg (maxWait 30 < holdMax 60), so it shows a deadline refusal, not the overtaking.
- stop_never_leased is stated on the pre-state; for non-tick events it allows the lease's release, its owner's clientGone, or a restart instead of leasesOn s r.id = [], because a release in the pre stage frees a resource the pump then evicts in the same step (r2 review: sound).
- Ticket creation on a refusal for cause is by definition; ticket_age proves only that the ticket's age is used. maxWait must exceed the wait for room, else jobs are refused before they fit.
- admit_fits/spawn_fits hold against the sampled footprint; OS footprint growth between ticks is outside the model (shed on the next tick).
- idle_stopped, start_bounded, stop_escalates are stated at tick time; their real latency adds the tick period (S4).
- reply_once holds per daemon life (runs without `.restart`); a restart drops every connection.
- holdMax must be at least the longest job's p99; renew is the heartbeat, capped by renewCap (lease_span).
- Nested joins (Core module doc): only the parent job lease id is checked, not its owner, and a child outlives the parent's release (deadline capped by the parent's); follow-up sup-wire.
OS assumptions (prose, never axioms)
- S1 Only the shell spawns, and only on a `spawn` command; grandchildren are covered by the process group, except S3.
- S2 (pid, start second) names one process; macOS does not reuse a pid within the same second (INFERRED, as `fw reap`).
- S3 killpg reaches every group member that did not call setsid. Escapers: lake serve file workers, the Chromium crashpad handler, Node `detached` children. They are stopped by the tick's ps descent through recorded ppid chains (reap backstop).
- S4 A tick comes at least every tickMax seconds; the clock is monotone (the model clamps a backwards `now`).
- S5 An exit is seen within one tick, for direct children only (SIGCHLD or the tryWait sweep); adopted children after a restart are not our children, so their exit is observed by the ps poll.
- S6 The ps/top sample is a snapshot good enough for identity; the start time is re-read before every signal.
Open items: shell (TS/Rust glue) not written; fwcore wire op and golden replay for run_eq_fold not done; trace-level fairness (needs the design change above); nested-join authorization.
Read first: design note (lead scratch daemon-design/design.md, lines 145-196), then Core `step`, then Props section headers.
