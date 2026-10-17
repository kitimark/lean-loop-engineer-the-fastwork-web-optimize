# lean-sched handoff

**State:** E7 (Admit) and E9 done on branch `worktree-agent-ac24bf04c5faab810` (commit: see `git log -- lean/Fw/Sched`).
`lean/scripts/check.sh` is green. The mathview lint reports 0 failures and 0 quantifier warnings on `Fw.Sched.*`. Only standard axioms are used, and there is no sorry.

**Modules** (`lean/Fw/Sched/`, both imported in `lean/Fw.lean`; NOT registered in `Fw/Wire.lean`, which is E8):
- `Admit` (67 theorems):
  - Definitions: `Item`/`State`, `admit` (the reasons `neverFits`/`depPending`/`writeConflict`/`deviceBusy`/`overBudget`/`behindAged`), `pick`/`chosen`, `admitStep`, `step` over `Cmd` (admit/finish/enqueue/tick), `Reachable`, and `Inv`.
  - Safety, over reachable states: `writes_disjoint`, `devices_exclusive` (related parent/child pairs exempt), `deps_respected`, `within_budget`.
  - Ordering: `aged_not_overtaken` (with `before σ.t z x`).
  - Liveness: `aged_admitted_by`, over `Trace B dmax` (each event = step then admit-all; the post-event clock stays below start + dmax for every item running before it).
- `ParMetrics` (33 theorems):
  - Intervals: `merge` (`merge_disjoint_sorted`, `merge_cover`).
  - Busy time: `busy` (`busy_le_alive`).
  - Speedup: `speedup` (`speedup_le_agents`).
  - Serial share: `serialShare` (`serial_share_le_one`).
  - Stretch: `stretch`.
  - Critical path: `cp`, a Kahn pass with fuel n (`cp_ge_path`, `cp_attained`, `cp_acyclic_or_error`).
  - Bench verdict: `benchVerdict`/`labeling` (`bench_wins_le_one`, via `Fw.Null.winsAt_le_one`; 1/70 guard).

**Restated vs plan §3.2:**
- `aged_admitted_by`: the plan's k-term bound is false.
  - Counterexample: the `Cex` guards. An older competitor `o` is not ready, and a newer `y` slips ahead of it, so z is still queued at t=25 > 20.
  - New bound: `σj.t < σi.t + (1 + Ψ)·dmax`, where Ψ = (queued older items that can ever fit) + (those not yet aged ∧ ready).
  - New hypotheses: `dmax > 0`, and σi is quiescent (`chosen = none`).
- `Inv` adds unique seqs, seqs below `next`, and start ≤ t. Unique ids give `x ≠ y` in the safety theorems.

**Conventions:**
- Core Lean only.
- Docstrings carry `$$` math with every binder quantified (lint-clean).
- Every decision function has a `#guard`.

**Open items:**
- The `comp` budget clause makes an aged over-budget item reserve room and block all items behind it. This is by design, per plan; see the `admitAll` guard.
- Wire ops and golden vectors (E8) are not done.
- Serial share uses breakpoints (a, b, all ends in [a, b]). Its exactness (equal to the measure of {p : busyAt ≤ 1}) is not proved, only ≤ 1.

**Read first:** the module docs and the `Cex` block at the end of `Admit.lean`; plan §3.2.
