# alert-rules-fix handoff

State: branch worktree-wf_c8c1d265-fc1-2; rules 1-6 done (commits c0f9ee49, 4a02a8fc, then the rule 3/5/6 commit and the final fix commit).
Verified: lean/scripts/check.sh green; apps/runner and apps/console-api `pnpm test` green; scripts/ci-paths.test.mjs green.

Rules (each Lean + golden + glue):
1. resume iff SubagentStart newer than stop: Fw.Ops.Obs (`stoppedAtOf`, `no_revive_after_stop`, `start_revives`), golden ops.obs.jsonl.
2/4. ci.failed per (workflow, branch, headSha) set, per-workflow ciSlowBy: Fw.Obs.Health, golden health.jsonl.
3. timing key has `kind` (runKind); alert only on ok->slow transition: Fw.Obs.Timing, Fw.Obs.Next (`slowLatestFrom`), golden timing.jsonl, next.jsonl.
5. Fw.Obs.Backoff (`onTimeout`, op obs.backoff, golden obs/backoff.jsonl); console-api core/lean.ts `backoffDecision` waits (1+extra) deadlines when load >= 50 (TS stand-in, checked by test/backoff.test.ts against the golden and fwcore).
6. Fw.Ops.Obs `alertTitle`: all-`sweep:*` issues get "Drain threw in fwcore: ..." title (`alertTitle_sweep`, `alertTitle_spool`, `alertTitle_le`); golden ops.obs.jsonl.
   Watch: readSweepErrors ignores a sweep-errors.json whose pid is not alive (apps/runner/src/watch-svc.ts). TS stand-in: only an isAlive check, not in Lean.

Open: `lake build fwcore` kind (rule 3 cache hit/miss) not observable; agent.held/killOrphan unchanged.
Conventions: regenerate goldens with ObsGolden/OpsGolden and NextGolden.run; never hand-edit.
Read first: research/notes/2026/10-19-alert-rules.md (Review corrections).
