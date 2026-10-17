# Handoff: lean-null-fix (fixes from the fwcore math review)

State: all 7 English overclaims of `research/notes/2026/10-17-math-review-fwcore.md` fixed, Null gaps A and B
closed by proof, wording notes applied. Branch `worktree-agent-ae169c980f8ea7d0a`, based on main c3f904b.
Gates: `scripts/check.sh` green (build, `lake test`, `mathview --lint`: 254 entries, 121 theorems, 0 failing,
standard axioms only; golden wire replies unchanged).

## Done
- Gap B (`Fw/Spec/Null`): `binom` (Pascal), `arr_length` (|arr(k,n)| = binom), `binom_succ_mul`,
  `choose_eq_binom` (the wire's multiplicative `choose` is exact for all k, j), `arr_length_choose`,
  `binom_pos`, `pAt_le_choose`, `pAt_le_pNull` (pAt <= pNull for any values, any m, n).
- Gap A: `winsAt_distinct` (any pairwise distinct values, m, n >= 3: exactly one winning labeling, via
  `exists_threshold` from `List.mergeSort`), `winsAt_tooFew`, `pAt_distinct` (pAt = pNull for distinct values,
  all m, n), `falseBetterProb_eq_pNull` (enumeration = closed form for every m, n).
- Item 2: `sel_idx` (sel(f, b, [0..|b|-1]) = ranks(f, b)), `wins_eq_winsAt`, `falseBetterProb_eq_pAt`.
- Item 4: `Console.step_twice` (second delivery: duplicate or the same outcome); `apply_idem` English trimmed.
- Item 5: `aged_beats_newer` retitled "Aging"; new `aged_not_overtaken` (an aged fitting job is passed only by
  older jobs) and `unfit_never_starts` (a job longer than the window is never started: real starvation case).
- Wording notes: free variables quantified (Null, Screen, DeviceQueue, ArtifactKey, Console, Board), `arr` map
  notation, `{false,true}`, `tick` parentheses, `check`/`cardRefusal` elided conditions written out.
- Docs: Null module text, README, `Fw/Wire.lean` docstrings of `opVerdict`/`opMultiplicity` (doc only).

## Needs re-review (statement or $$ changed)
New: Null binom, binom_zero_right, arr_length, binom_eq_zero, binom_pos, binom_succ_mul, choose_eq_binom,
arr_length_choose, pAt_le_choose, mem_arr_iff, sel_cons, length_sel, count_true_add_false, winsAt_tooFew,
pAt_le_pNull, countP_lt_getElem, exists_threshold, sel_map, winsAt_distinct, pAt_distinct, idx, idx_nodup,
sel_range'_zipIdx, sel_idx, wins_eq_winsAt, falseBetterProb_eq_pAt, falseBetterProb_eq_pNull;
Console step_twice; DeviceQueue aged_not_overtaken, unfit_never_starts.
$$ edited (Lean unchanged): every declaration in the wording-notes list, plus Null arr, choose,
better_labeling_unique, DeviceQueue tick, Console check, cardRefusal.

## Open
- Starvation-freedom of `dispatch` as a liveness property (over a run of dispatch/tick steps) is not stated; only
  the per-step lemmas above. A job longer than every booked window starves by design (`unfit_never_starts`).
- The L3 premise (exchangeable runs give uniform labelings) stays a modeling assumption.
