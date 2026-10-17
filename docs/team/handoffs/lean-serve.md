# Handoff: lean-serve (stateful `fwcore serve`)

State: branch `worktree-agent-aa3e2a69b982250f3`, one commit on top of main aa7b729 (see `git log -1`).

## Done
- `lean/Fw/Serve.lean`: pure core `Fw.Serve.exec : Srv → Cmd → Srv × Resp` (apply / replay / query / reset).
  `Srv` = arrays + hash indexes (`Tbl`) + seen hash set; `Srv.st` is the `Fw.Console.State` it stands for.
  Proved: `fcheck_eq`, `faccept_st`, `fstep_spec` (same decisions as `check`/`accept`/`step` on an `Indexed` server),
  `run_eq_fold`, `run_init_eq_project`, `apply_each_eq_replay`, `run_reset`, `refused_unchanged`, `accepted_changed`,
  `query_keeps`, `query_eq_of_st`, `query_after_run`, `fastBoard_eq` (one-pass board = `Fw.Console.board`).
- Glue in `Fw.Wire.Serve` (same file, outside the math view): `serveLine` (stateful ops first, else `Fw.Wire.handle`),
  `loop` (one `IO.Ref.modifyGet` per line), `boardGolden`. `Main.lean` calls `Fw.Wire.Serve.main`; `Wire.lean` only lists
  the 3 new op names. A `console.apply` with a `state` field is still the stateless op; `console.board` unchanged.
- Board goldens: `lean/golden/console-board.jsonl` = `packages/contracts/golden/console-board.jsonl` (19 cases, with the
  event log); regenerate with `cd lean && lake env lean --run scripts/BoardGolden.lean`; `lake test` checks both files.
- TS: `LeanCore.open(log)` replays events.jsonl lines (20k per request); every respawn replays again before its first
  call; a failed replay poisons the child (calls fail, no partial state). `apply(event)`, `board(now, seq)` (query),
  `restart()`, `applyPure`/`boardPure` (goldens). Store: `state` field removed, minimal call-site change.
- Measured (console-api `test/serve.test.ts`, 100,008 events, 4,167 cards): replay ≈0.4 s, apply RTT p50 ≈40 µs,
  p90 ≈100 µs, query ≈40 ms (was ≈0.6–1 s with the list board). Old list reducer: 36 s for the same replay.

## Conventions
- Code that updates arrays destructures the structure first (`match t with | ⟨rows, idx⟩ => …`) so Lean updates in
  place; `Tbl.push_eq`/`modify_eq` give the projection form for proofs. Keep that when editing.

## Open
- `lean/README.md` op table and `apps/console-api/README.md` not updated (not my files): add replay/query/reset.
- `scripts/check-partial.sh` does not scan `Fw/Serve.lean` (it has no bang accessors; add it to the list).
- PLAN hardening item 1 (id mismatch kills the child) and the per-call timeout are still not implemented in lean.ts.
- A torn tail line written after the last open makes every restart replay fail until console-api restarts.
