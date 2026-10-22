branch: worktree-wf_d01aef35-e6a-1
worktree: .claude/worktrees/wf_d01aef35-e6a-1
last commit: see `git log -1` on the branch
CI runs: none (pure Lean/TS change; no CI-measured result, no ci/* push).

Final design round (graph r281/r286/r287). Design: the verdict reads the ms spent under each wait reason, not holder lease shapes.
- Lean `Fw.Sup.Adapt`: `WhyTag`, `Why.tag`, `WhyTag.name/all/ofName?` (the one list of reason names; golden line `adapt.whyTags`).
- Lean `Fw.Obs.Timing`: `Sample.waits`, `holderWait` (allowlist, false only for memory/memLow), `Sample.holdMs`, `queuedWithin s := 0 < holdMs`,
  `rest` judged on `durMs - holdMs`. Deleted: waitOverrun, graceMs, overrun branch, overrun_slow, leaseMs.
  Proved: queued_not_slow, queued_iff, nonholder_judge, rest_ge, judgeQ_unwaited (hyp holdMs = 0), judgeQ_queued/plain.
- Wire `Fw.Wire.Obs.waitsOf`: closed parse (unknown names dropped). Goldens regenerated: timing.jsonl (12 queue cases), sup/adapt.jsonl.
- TS: `slot-queue.ts` (`addWait`, `queueOf`, `parseWaits`, `WHY_TAGS` = TS stand-in for WhyTag.all, checked vs golden),
  `slot.ts` acquire adds (v.why, ms since previous poll), `timing.ts` Span type, `watch-collect.ts` parseSamples.
- Split out: "holder lease overrun stays an alert" -> task timing-lease-overrun (not here).

Accepted limits: forever-renewing or legacy sim-lock holder makes waiter time queued; a refusal (maxWaitS / --wait) has no queue and is judged
plain (the remaining alert path); memory/memLow wait stays judged; allowlist is reviewed, not proved from verdictWith; per-reason ms from poll
timestamps (the last interval before admit is not counted); waitMs is display only.
Read first: header of lean/Fw/Obs/Timing.lean, then apps/runner/src/slot-queue.ts.
