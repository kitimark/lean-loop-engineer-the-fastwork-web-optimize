# sup-fairness handoff

State: branch `worktree-wf_c2b0e206-401-1`, base 7267a8f0; see `git log` for the head commit.

Done (all in `lean/Fw/Sup/Core.lean` and `lean/Fw/Sup/Props.lean`, no new module):
- Core pumpOne: a svc grant on an unpinned resource waits behind a blocked job; the deadline refusal keeps a ticket
  (`refuseT`).
- `fifo_no_overtake` for every grant, `svc_respects_blocked` as its A = [] corollary, `deadline_keeps_ticket`.
- `Ex.slow`, `Ex.starve`: Fable's witness on the pre-fix pump, quoted as a negative example.
- `head_job_granted_by` (section "Head job granted"): HJ invariant, Pot potential, per-event `*_pf` lemmas,
  `pump_blocked`, `fresh`, `hj_step`, `hj_run`. Bound `span + tm + K·(killAfter + 2·tm)`, K = `unpinned c s`.
- Non-vacuity: `Ex.patient`, `Ex.blocked`, `Ex.renewed`, `Ex.head`; the theorem applied to the trace (granted at 176,
  bound 200), Room at the start by decide; `alongB`/`along_of` decide `Along`.
- design.md rows: reply_by_deadline, fifo_no_overtake, head_job_granted_by; pending prose on kept ages.

Deviations from the spec hypotheses (on s, documented in the docstring):
- extra: queued requests behind q are no older, `q.age ≤ s.now`, `s.draining = false`, stopping resources at s are
  unpinned and began by `s.now`. None follow from `Inv`; a sorted-queue invariant would remove the first.
- H5 is stated as "a tick finds no resource in `stopping _ .kill`", H4 as "each tick ≤ clock + tm".

Open follow-ups: sup-fairness-psi (job at position k), sup-fairness-svc (svc progress), needed-set in Acc, a
sorted-pending invariant to drop the ages hypothesis.

Read first: Props.lean `/-! ## Head job granted -/`, then `hj_step` and `head_job_granted_by`.
