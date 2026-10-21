# toolbar-throttle-probe (measure-engineer) handoff

State: branch worktree-wf_fdce5e0d-d9c-1 (CI branch ci/toolbar-throttle-probe, tip 525ac1c0 when measured). Lean check.sh green.

What exists
- Lean `lean/Fw/Device/StillRuns.lean`: still-run count (band 5-6 frames, short 1-9, exit frames), `throttleK`, `Verdict`
  (lifted / notLifted / noData / confounded, one theorem per branch). Golden `golden/device/stillruns.jsonl`, twin
  `packages/measure-webkit/src/throttle/stillruns.mjs`.
- Diagnostic flag `engine.scroll:throttle-lift` (part.json `diagnostic: true`, `throttle.ts`); in no preset, never ship it.
- Harness `packages/measure-webkit/src/throttle/`: XCUITest touch driver (`driver/`, xcodegen), recorder, probe, report, cli
  (`build-driver`, `run`, `report`). Workflow `.github/workflows/toolbar-throttle.yml` (push token `[ci:toolbar-throttle]`).
- Lean CI rows added: Trigger, Intent (macosFiles), Overflow (width 3), Pool/Caps (excluded, no measured cap yet), Steps; goldens regenerated.
- Note `research/notes/2026/10-2x-toolbar-throttle.md` has the table.

Verified: CI run 39667548341, 3 of 3 jobs `lifted`: rewrite 163 band runs / 10,104 exit frames, lift 0 / 9,740, original 53 / 5,290.
Earlier runs 39659502492 and 39652336316 read as failed in fw ci state (harness lost the first pass); the note lists both with the reason, not pooled.

Round 2: main merged (check.sh green, dry land VERDICT dry with --allow for the CI-row files the lead accepted); no new CI runs.

Open
- Phone pass not done (device-replay driver not landed): compare production build with and without the flag at the same
  viewport, count with `stillruns.mjs` (note section "Phone pass").
- Pool/Caps: add a measured cap for `toolbar-throttle.yml sim` after a few runs (job time 25-45 min on the runner).
- If the flag helps on the phone, the shipped candidate is the threaded scroll-driven exit (`hero-exit-threaded-port`), not this flag.

Conventions: the driver is built before the Simulator boots (a build next to it starved Safari); one unrecorded warm-up
session first; a pass is retried once; the harness logs every 30 s while touching (stall watchdog 300 s).
Read first: the note, then `cli.mjs`, then `StillRuns.lean`.
