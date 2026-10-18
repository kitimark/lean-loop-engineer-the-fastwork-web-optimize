# Handoff: math-final (r14 delta fixes)

State: branch `worktree-wf_3504c87c-4b0-6`, commit "math-r14-fix" on f9b30af. Record
`research/notes/2026/10-18-math-review-r14-f9b30af.md` (round 14; the four r14 batches merged into one file because
build-math-view refuses two records of one round).

Done: all 91 r14 disagreements fixed by docstring math only; no Lean body or statement changed (not_fixed empty).
Files: Ci.{Intent, Trigger}, Measure.{Retry, StepAlign, WktrLayout}, Obs.{Health, Next, Signals, Stale},
Ops.{Cache, EnginePremise, LeanFirst, LeanFirstProps, LeanFirstSearch, Premise, Wait}, Parts.{Golden, PeopleCard,
PeopleDeck}, Sched.Admit, Site.Reference, Spec.Incidents.

Also fixed, because they blocked build-math-view.mjs (broken on main since r12; the view was last built at r10):
- dangling-where: Measure.SelfCheck.maxDiff_zero_iff, and one I had introduced in Obs.Next.Branch;
- KaTeX strict errors: Unicode ␣, ⏎ and ≤ in math became `\char"2423`, `\char"23CE` and `\char"2264` (Ci.Budget,
  Ops.{Wait, LeanFirst, LeanFirstSearch}, Engine.Chromium, Measure.EngineCheck, Parts.{HeroAccent, HeroExitOpt,
  HiddenPause, MorphMountOpt, MorphPanelOpt, NavHitTestOpt, PainNotes, PeopleCard});
- `\"` inside `\texttt` (Parts.HiddenPause), `$$` in prose (Ops.Wait.opd), missing `$` (Console.PreviewTable.factJson).

Verified: `lake build` passes (64 s); mathview lint 0 failing; docs/plan/loop-plan.html regenerated: 5271 agree,
0 disagree, 355 stale, 1151 pending.

Open:
- Round 15: re-review the 355 stale rows (they include the 91 fixed here).
- 1389 pending entries held back from r14 (Gate.*, Plan.*, Console*, Engine*): see `node scripts/math-pending.mjs`.
- The six-point docstring checker was not spawned (this run had no agent tool); run it in round 15.

The builder stops at the first KaTeX error. To find every error in one pass, render each $$ block of the export with
`katex.renderToString(..., {strict: 'error'})`.

Read first: the r14 record, then `scripts/math-pending.mjs`.
