# math-r12-fix handoff

Source: `research/notes/2026/10-18-math-review-r12-6504ec1.md` (12 disagree rows). Docstring-only edits, no Lean code changed.
`lake build` green, `mathview-cached.sh` 0 failing, no sorry or axioms added.

Fixed (10):
- `Fw.Ci.Budget.statusOf`: math now says 2nd non-empty space token via `String.toNat?` (also accepts `1_000`).
- `Fw.Measure.Quiet.Verdict`: structure math `(cls, kept, total) in N^3`; the cases stay with `verdict`.
- `Fw.Measure.Freeze.RunTable`: type renamed in the math (Run -> RunTable).
- `Fw.Plan.Core.mk` (Fw.Plan.mk): 12-tuple with cut=false, live=[], W=[] by default.
- `Fw.Plan.Graph.cpf`: `look(tab(ts,k), x)` instead of undefined T_k.
- `Fw.Parts.MorphTween.pointerNone_iff`: forall m in Q, no m >= 0 hypothesis.
- `Fw.Parts.MorphMount.Action.after`: after_d with the none case = d.
- `Fw.Parts.MorphMountGolden.rin`: mantissa n*floor(1000/d), exact iff d | 1000.
- `Fw.Parts.MorphMountGolden.rects`: lists all 14 triples.
- `Fw.Parts.MorphMountGolden.lines`: concatenation order, 74 lines.

Deferred (2, files owned by integrate-ports):
- `Fw.Gate.pilotParts` (lean/Fw/Gate/Scope.lean): math lists 6 parts, Lean has 8; add morph.mount after hero.exit and morph.tween last (see note row).
- `Fw.Parts.Golden.tweenLines` (lean/Fw/Parts/Golden.lean): replace placeholder `lines` with the ordered concatenation (ease 9, tween 55, dir 10, armed 9, taken, active 8, fade+pointerNone 9, push, frame).

Note: `scripts/wt-prep.sh` skipped the clone because a `lean --server` in main counts as busy; I cloned `.lake` by hand.
`scripts/mathview-cached.sh` lives at `lean/scripts/`.
