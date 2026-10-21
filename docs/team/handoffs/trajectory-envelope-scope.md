# Handoff: trajectory-envelope-scope

State: branch `worktree-wf_da1a1d10-06c-2`; the commit that adds this file is the tip. `reduce.mjs` is unchanged.

Decision: keep the envelope's scope (every in-flight sample, no own-pass fallback while another pass has a core).

Verified:
- Lean `Fw.Gate.Trajectory`: `startOf`, `atStart`, `judgeScoped` (the rejected scope, Lean only, with `#guard`s);
  `judgeScoped_start`, `judgeScoped_later`, `judgeScoped_stuck_hold` (scoped passes a stuck hold, the envelope fails it),
  `judgeScoped_other_curve` (the envelope passes another pass's curve past the start, scoped fails it),
  `judgeUnit_sound` (beyond every reading of the whole path never passes, every branch, colour channel and alpha),
  `judgeUnit_mutations`, with `mem_flightWindow_core`, `flightWindow_core`, `envelope_core`, `Outside.sub`,
  `Outside.samps`, `judgeEls_outside_not_pass`. Standard axioms only.
- Golden: 2 flipped cases renamed ('in flight, a pass the original lacks, beyond pass 0' / '... inside pass 0'),
  3 new `casesClose` cases; 220 lines, `--check` up to date. TS test replays them; scope test against `judgeOwn`.
- gate-breakpoints tests 425/425, contracts tests, `scripts/ci-paths.test.mjs`, runner land-inputs, `lean/scripts/check.sh`.
- Six runs re-reduced (16 artifacts): 0 units change against main. Counts table and every close-start cell explained (one close-hold cell added after review)
  in `docs/team/tools/trajectory-probe.md`, section "Envelope scope".

Findings (MEASURED, scratch only): `judgeScoped` re-fails 20 faithful-arm units, same 52 candidate `new`. A core of any
phase (drop `o.ph == r.ph` in `isCore`) gives 381 / 392 / 46 and clears 39466179818 mac 640 bg close-hold@0.

Open: same-phase core starvation at the push/hold boundary (follow-up task, not adopted); A/A 39472217441 mac 390 bg
close-hold@0 is a pass lagging beyond the 200 ms slack under every rule.

Read first: the "Envelope scope" section of trajectory-probe.md, then `judgeScoped` and `judgeUnit_sound`.
Re-reduce: `gh run download <id> -p 'trajectory-*' -D <new dir>`, convert colours with `colourFromV1`, `reduceRaw`.
