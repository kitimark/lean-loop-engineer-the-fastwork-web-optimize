# commission-band-followups (lean-prover)

- Branch `worktree-wf_26df5fbd-a3a-1`, worktree `.claude/worktrees/wf_26df5fbd-a3a-1`; work commits e3742c18f (Lean,
  goldens, TS replay) and 91735b0a2 (note); main merged after them.
- CI: none dispatched. Figures come from downloaded artifacts of runs 39837044649 (base), 39843560957 (v2 flag),
  39837049981 (v1 flag).
- Verified: `lean/scripts/check.sh` green; `@fw/site` tests (6503 passed), typecheck, `scripts/ci-paths.test.mjs`,
  runner `land-inputs.test.ts`.

## State
- `lean/Fw/Parts/CommissionOpt.lean`: a tick is an optional media event, then an optional body (`Tick`, `mV`, `mO`).
  Premises `Reads`, `MediaOnFlip` (P1), `BodyAfterSkip`. Look agreement over the merged trajectory under either premise:
  `look_agree_merged`, `commission_visSame_merged`. The `#guard` on `exRun` shows the looks differ when both fail.
- `CommissionOptGolden.lean`: 5 `mergedTrace` lines in `commission-gate.jsonl` (75 lines in total). The last line is
  the counterexample. `apps/site/src/parts/commission/bandgate.test.ts` replays them through the real driver.
- Note `research/notes/2026/10-2x-commission-band-gate.md`:
  - "Premise P1 (source)": P1 is CONFIRMED in HTML and WebKit. In Chromium it does not hold (the event is deferred
    past paint or dropped). Chromium keeps the look through `BodyAfterSkip`.
  - Measurements: half-open window `3070 <= scrollY < 3530` (46 frames); flag 3.09 and 60.9 (the old 3.07 and 60.1
    were the v1 flag run).

## Open
- Lead edits: `research/findings/ledger.json` row 48 and `docs/team/handoffs/commission-band-gate.md:13` still cite
  3.07 and 60.1.
- Still INFERRED:
  - WebKit: no viewport change lands inside one rendering update.
  - Chromium: the rAF the driver requests runs in the next painted frame (throttled frames not read).
- `bandgate.test.ts` lies outside this task's write list.

Read first: the note's Lean table and P1 section, then `CommissionOpt.lean` from `structure Tick`.
