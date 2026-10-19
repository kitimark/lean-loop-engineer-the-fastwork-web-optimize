# Handoff: countdown-hidden-pause (O2)

State: branch `worktree-wf_176e2293-c7b-2`, fix round 1 at 9a59903d (main merged first). Round 0: Lean 7dd3aa7f, TS
9a1d2f87. Round 1 drops the far (IntersectionObserver) branch: the gate is closed exactly when the written
`--exit-opacity` is 0, and it reopens on the same MutationObserver read that sees exit > 0.
Gate run: round 0 dispatched one Chromium breakpoint-gate (fw=hero.countdown:hidden-pause, run 39205809122). Its
hero.countdown row passes in desk, desk-rm, touch and all 3 sweeps. The merged verdict `refused` comes from the
narrowed run itself: narrowed runs never exit 0 (`narrowed_never_zero`), and the summary is missing `--parts`, an open
item already listed in docs/team/handoffs/gate-no-skip.md:23-25. Round 1 only removes the far signal from the TS gate,
so it needs no new run.
Verified (round 1):
- `lean/Fw/Parts/HeroCountdownHidden.lean`: `lake build` passes (518 jobs, 38 s). Axioms are only propext,
  Classical.choice and Quot.sound. New: `farAbove_implies_exitZero` (t + h < −v gives exit 0) and
  `farBelow_unreachable` (T < 2v and y ≥ 0 give T − y < 2v). `hidden_iff` now has one branch (x = 0), `hidden_iff_exit`
  is unconditional, and `gatedInstance` is the hero-only predicate. `ClockIn`, `grow`, `farOff`, `scene_empty_of_far`
  and `hidden_iff_far` are removed, and `visSame` no longer takes R or `hIn`.
- Golden `hero.countdown.hidden.jsonl` was regenerated with no `far` field. `reduced-far` and `far-below` are now open.
  `--check` passes (13 lines).
- Footprint was regenerated (`part-footprint.mjs --write`; ContractsGolden `--check` passes for all 5 files).
- Tests: site vitest 5174 pass, site tsc clean, ci-paths 32 pass, runner tsc clean, land-inputs 40 pass.
TS: `hidden.ts` (`countdownHidden(exit)`, `gatedInstance`, `installHiddenGate(root, MO)`). index.tsx uses
`gatedInstance`. part.json limit: under reduced motion the gate never closes.
- Land fix (after merge 86d40878): `v2-proved.decisions.jsonl` was stale because the generator reads every part.json
  variant. It was regenerated with `Fw.Preset.Gen.run []`: one new row, `hero.countdown:hidden-pause`, `member:false`,
  `no-link` (not in `links`). The preset is unchanged (the same 10 flags). The lead adds preset entries.
Open:
- Measured verdict: from the wave-2 whole-page run.
- A morph.countdown comment says its IO runs "before paint", but IO is a posted task
  (intersection_observer_controller.cc:90-97@f842f52). That file is outside this task's write set.
Read first: the Lean module §2–§3 (the redundancy theorems and the decision), §6 visSame, then `hidden.ts`.
