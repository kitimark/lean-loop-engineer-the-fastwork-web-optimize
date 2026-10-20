# watch-incremental handoff

State: branch worktree-wf_e81e50b2-df2-1 (see git log). `sh lean/scripts/check.sh` green, `pnpm test` in apps/runner 1473 pass, ci-paths test pass.

What exists
- lean/Fw/Obs/Fold.lean: `feed` (fold over lines), `lines_append`, `feed_append`, `pass_eq_full` (saved state + appended complete lines
  + unterminated tail = whole-file read), `chain_inv` (any number of passes), `cut_*`, `decide` with one theorem per refusal branch
  (`decide_schema/code/shrunk/inode/anchor`) and `decide_resume_iff`. Golden: packages/contracts/golden/obs/watch-fold.jsonl, written
  and checked by `lake env lean --run scripts/ObsGolden.lean [--check]` (Fw/Obs/Golden.lean).
- apps/runner/src/watch-fold.ts: summarizeTranscript + signalsOf as one fold (state, step, finish, save, load).
  apps/runner/src/watch-cache.ts: `decide`, `cutAt` (both checked against the golden), `foldFile` (chunked read, resume, atomic save to
  <consoleDir>/watch-cache/<sha1>.json; key = FOLD_SCHEMA + hash of watch-fold.ts and watch-cache.ts).
  watch-collect.ts: readTranscript(tf, id, p) uses it; collectAgents memoizes each spool file's summary by (size, mtime).
  The stoppedAt-with-worktree filter is unchanged (a memo of a pure function changes no decision).
- Tests: apps/runner/test/watch-fold.test.ts.

TS stand-ins (not Lean-checked): the step bodies (JSON to fields) in watch-fold.ts; foldFile I/O. Their incremental = full property is
tested at every 7th byte cut of a fixture, and by a replay over 120 real transcripts x 6 random byte cuts (840 checks, 0 mismatches,
720 resumed). Old and new collectAgents are byte-equal on a frozen clone of the spool and transcripts (74 agents).

Accepted limits: the anchor is the last 64 bytes before the offset, so an in-place edit earlier in the file is not seen (transcripts
only grow); the mtime prefilter (Fw.Obs lemma lastAt <= mtime) is NOT done, a follow-up; cache files older than 7 days are swept once
per process; the open-lead-steps alert belongs to alert-resolve-keys; the reapable line is a later task.

Read first: lean/Fw/Obs/Fold.lean, then foldFile in watch-cache.ts.
- Deviation from the old full read: a JSON `null` line is skipped (the old read threw and showed no transcript); the recorded corpus has none.
