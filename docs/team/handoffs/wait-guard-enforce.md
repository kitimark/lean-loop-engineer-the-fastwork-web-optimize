# Handoff: wait-guard-enforce
State: branch worktree-wf_59731989-59c-1, commit a51555d (+ this note). check.sh green, runner 633 + contracts 7 tests pass.
- Shadow review (MEASURED, main spool, 643 WaitGuard records, commands recovered from transcripts by tool_use_id):
  old rules 5 deny:unboundedLoop, 4 false positives (3 `while read ...; done < file`, 1 here-doc body with a `while`
  line), 1 true positive (`until [ "$(gh run view ..)" = completed ]; do sleep 150; done`, no counter).
- New rules (Lean Fw.Ops.Wait): 642 allow / 1 deny on the real log (FP 0/642); synthetic corpus 50 rows, 0 mismatches.
- Lean changes: Term.pipe (`|` vs `&&`/`||`), here-doc bodies skipped (hereDelim, bodyStep), `key` skips `do then else`
  so `do while true` is seen, read loops (isReadLoop, finiteRedir, finiteProducer, UAcc.stack). Theorems:
  readLoop_bounded, plainLoop_free, addSeg_inner/addSeg_body, heredoc_body_inert, heredoc_line_inert; bg_long_denied and
  deny_iff_check unchanged. #guard examples at the end of Wait.lean.
- Goldens: packages/contracts/golden/ops/ops.wait.jsonl (39 rows; `lake build Fw.Ops.Golden` before OpsGolden.lean,
  else a stale olean writes the old rows). Tests: apps/runner/test/wait-guard.test.ts (shadow FP block).
- Enforce switch (lead hands to the user, not done): `{"mode":"enforce"}` in main `.fw-console/wait-guard.json`,
  or FW_WAIT_GUARD=enforce; revert with `{"mode":"shadow"}`.
Open: blind spots in docs/team/tools/wait-guard.md (`$( )`, `sh -c` strings, `<<EOF>f`, one bound word bounds all
loops of its unit). No checker run: this agent had no subagent tool; docstrings self-checked against the 6-point list.
Read first: docs/team/tools/wait-guard.md, then lean/Fw/Ops/Wait.lean (Parsing, Shapes and units sections).
