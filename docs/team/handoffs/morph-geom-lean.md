branch: worktree-wf_f89668d1-656-1; worktree: .claude/worktrees/wf_f89668d1-656-1
last commit: this handoff's commit, on top of fe1b83537 (main merged at 52f0a1894)
CI runs: none (Lean only; the accepted limits rule out CI)
verified:
- check.sh green via `fw slot run --kind check` (4:28), including the `morph-geom golden check` job.
- plan lint: 0 errors, no writesClosure finding for this task.
- Tests pass: ci-paths 56/56, contracts 11/11, runner land-inputs 73/73.
- `#print axioms` standard on every main theorem.
done: every statement of the design note's Lean list. See research/notes/2026/10-2x-morph-geom-lean.md for the table.
- MorphGeom.lean: tracks, chords, sizes, clip doors, net_err.
- MorphGeomRect.lean: rect_eq, fill_eq, panel_eq, fade_eq, logo_err.
- MorphGeomEarn.lean: earn_eq for WebKit and Chromium.
- MorphGeomAnim.lean:
  - AnimProp, Anim, layers, anims;
  - accelerable_bands, noTransition_bands;
  - end_eq;
  - mem_bands.
- MorphGeomGen.lean writes packages/contracts/golden/morph-geom.jsonl. Its fn kinds:
  - knots;
  - time;
  - sample: eval at 11 m points, rounded to 6 decimals;
  - flip;
  - goal.
- check.sh job; Trigger.lean lean.yml row; triggers.jsonl regenerated.
finding:
- mem_bands: the census fits the 23,055,555 B headroom only on 320×568 and 641×700.
- The veil and platform backings dominate; the design must shrink them or measure what the faithful arm already pays.
open:
- morph-geom (site half) consumes the golden. The DOM contract is `data-mg="<el>"`, plus `data-i`/`data-j` on columns
  and images.
- The TS track builder must reproduce the `sample` lines within 1e-6.
- The memory verdict needs a design decision before morph-geom lands.
conventions:
- decide +kernel over bandVps for numeric facts; grind for Rat algebra.
- Golden constants are `(_ : Unit)` functions; the init cost lint refuses closed constants.
read first: the note above, then MorphGeomAnim.lean (anims, Ctx.sample) and MorphGeomGen.lean.
