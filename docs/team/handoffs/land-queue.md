# land-dry + land-queue handoff

**State.** Branch `worktree-agent-afafd6af558570fb5`. Commit 1 (`17b384b`) is land-dry; commit 2 is land-queue. Runner tests, `lake build` and the mathview lint were green (0 failing) before the main merge.

**land-dry.** `pnpm fw land <branch> --task <id> --dry` builds the real land's merge-tree commit, checks it in a land-wt slot (a pid claim, no land lock) and runs the scope, conflict-marker and reads stages (`land-inputs.test.ts` only when the change selects `apps/runner`). It never touches main, the lock or the queue. Kinds: stale (branch lacks main), scope, conflict, reads, dry, done. Lean: `lean/Fw/Console/LandVerdict.lean` (kinds, exit codes, `VERDICT` line), `LandDry.lean` (`dry_pass_land_pass`, `dry_refusal_is_land_refusal`, `handback_pass_land_pass`). Hand-back rule: `docs/team/token-policy.md`, section "Hand-back rule".

**Verdict lines.** Every `fw land` ends with `VERDICT <kind> <task>`; exit codes busy 10, dirty 11, scope 12, reads 13, conflict 14, checks 15, stale 16, unknown 2, done/dry/queued 0.

**land-queue.** `fw land --queue <branch> --task <id> [--allow g] [--no-run]`, `fw land --queue-status`. Log `.fw-console/land-queue.jsonl`, runner lock `.fw-console/land-queue.runner` (pid + `ps lstart`). Lean `lean/Fw/Console/LandQueue.lean` (FIFO, bounded retry of busy/dirty, runner identity). `Branch.inLandQueue` joins `Branch.locked` in `Fw/Obs/Next.lean`; theorem `no_unlanded_while_queued`; wire field `landQueued`; `next.ts` sets it from the pending branches.

**TS stand-ins (for fwcore replacement).** `apps/runner/src/land-verdict.ts` (dryKind, exit codes) and `apps/runner/src/land-queue.ts` (step/pending, retryAfter, runnerLive). Both are checked against `packages/contracts/golden/console/land-dry.jsonl` and `land-queue.jsonl`. Regenerate: `lake env lean --run scripts/LandDryGolden.lean` and `scripts/LandQueueGolden.lean` from `lean/`; the obs.next golden through `Fw.Wire.Obs.NextGolden.run "." true`.

**Land with `--allow`.** `lean/Fw.lean`, `packages/contracts/golden/**`, `apps/runner/src/land-*.ts`, `apps/runner/src/next.ts`, `docs/team/token-policy.md`, `docs/team/handoffs/**`.

**Open.** `math-reviewer` not run on the new entries (agents here may not spawn it). The runner does not wake on a new enqueue while another runner works: the working runner re-reads the log after each land and after releasing the lock. Queue overhead on a 3-branch fixture (local, in-process): about 10 ms per land.

**Read first.** `lean/Fw/Console/LandQueue.lean` header, then `apps/runner/src/land-queue.ts`, `docs/team/tools/land.md`.
