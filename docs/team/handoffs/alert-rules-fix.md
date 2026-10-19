# alert-rules-fix handoff

State: branch worktree-wf_c8c1d265-fc1-2; rules 1-7 done; see `git log` for the final fix-round commit.
Verified: lake build Fw; goldens regenerated and `--check` jobs in lean/scripts/check.sh; runner and console-api tests; ci-paths test.

Rules (each Lean + golden + glue, judged on its own):
1. Resume: `Fw.Ops.Obs.epochNext` (stop sets epoch, a later start resets it to 0), `heartbeat_after_resume`, `silent_after_stop_epoch`; stop, start, tool gives a heartbeat (golden ops.obs.jsonl). console-api spool/drain.ts takes the epoch from Lean.
2/4. ci.failed per (workflow, branch, headSha); per-workflow ciSlowBy (`Looser` monotone per workflow): Fw.Obs.Health, golden health.jsonl.
3. Timing key has `kind`; windows never mix kinds (`mem_window_key`, `mem_window_kind`); alert on ok->slow only (`slowLatestFrom`, Fw.Obs.Next).
   Kind is written: runner timing.ts `recordRunKind` (dispatch input digest, 12 hex, run-kinds.jsonl beside the timings file) and `ciSpans`/`recordCiRun`; chromium-counts gets the digest, every other step kind '' (test: span line round-trips kind in test/timing.test.ts).
5. Fw.Obs.Backoff `onTimeout`, op obs.backoff, golden obs/backoff.jsonl incl. a no-params case; TS `backoffDecision` is a stand-in.
6. `alertTitle` for sweep:* issues (Fw.Ops.Obs).
7. Dead session: hook emit.mjs writes `session_pid` (nearest claude ancestor; omitted when none, then nobody is judged); collector reads `alivePids`; `Fw.Obs.Health.settle` (`dead_session_done`, `alive_session_same`, `unread_table_alive`, `listed_pid_alive`) applied in `opHealth`; 3 typed goldens in health.jsonl.

TS stand-ins: backoffDecision (console-api core/lean.ts); watch-svc readSweepErrors isAlive check; the pid scan in emit.mjs and watch-collect (I/O).
Open: `lake build fwcore` kind (cache hit/miss) is not observable (accepted limit); agent.held/killOrphan unchanged.
Conventions: regenerate with ObsGolden, OpsGolden, TimingGolden scripts (and NextGolden.run); never hand-edit.
Read first: research/notes/2026/10-19-alert-rules.md (Review corrections).
