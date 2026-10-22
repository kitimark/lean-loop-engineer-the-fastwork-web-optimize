branch: worktree-wf_3a9b95a9-889-1
worktree: .claude/worktrees/wf_3a9b95a9-889-1 (of the main checkout)
last commit: 736aca77 (main merged); check.sh green, runner tests 2565 pass, dry land ok
CI runs: none pushed yet (no ci/disk-gc-tmp branch)

State
- Lean `Fw.Ops.DiskGc`: class 7 `usertmp`, `Cand.uid : Option Nat` (unknown owner kept), `sym`, class 4 split into
  age / pressure / owner branches, theorems `rule_usertmp`, `usertmp_named`, `unknown_owner_kept`, `rule_scratch`,
  `scratch*_spec`, `pressure_only_lowers`. Golden `packages/contracts/golden/ops/diskgc.jsonl` (43 cases) regenerated.
- Glue: `apps/runner/src/disk-gc.ts` (class 7, `--tmp-h`, `--pressure`, `gatherEventFacts`, `ownerMarker`, freed per
  class), `watch.ts` (pressure on both sys.diskLow triggers), `run.ts` (F3: mkdtemp per call, removed in finally).
- `scripts/lint-tmpdirs.mjs` + test: report-only (63 of 409 test files flagged), `--strict` exits 1.
- Docs: `docs/team/tools/disk-gc.md`, `disk-cleanup.md`.

Verified: lake build Fw (0 warnings); lint tests 36 pass. Check the final report for check.sh, runner test, dry land.

Open
- F2b is inert: nothing writes `.fw-owner` {task, run} in spawn glue (follow-up).
- F3 uses try/finally as the lead's text says; the checker preferred remove-after-success-only (a failed ingest loses
  the download).
- TS stand-ins: `gatherEventFacts`, `ownerMarker` parse, the lint heuristic.
- Follow-ups: fix the 63 test files the lint flags; the 78 GB X folder under var/folders; F2c pin expiry (rejected);
  F4 `pnpm store prune` stays a user step (disk-cleanup.md).

Read first: docs/team/tools/disk-gc.md, lean/Fw/Ops/DiskGc.lean (class 7, scratch branches).
