# Handoff: plan-rev11 (plan-editor)

**State.** PLAN rev 11 committed on branch `worktree-wf_9847872a-d87-4` (base main 16207afb); see `git log -1` there.
Files: `docs/plan/PLAN.md` (about 1,340 lines), `docs/plan/loop-plan.html` (status block, rev 11 list).

**What rev 11 adds.**
- §4.8 composition: units add up (`frameWork_append_units`, `frame_le_append_units`); passes do not
  (`frame_le_append_passes_fails`); the page condition is per-part `unionLe` or cover; F6 is units-only.
- §6.8 part contract: 34 rows, I1-I5, `affects`, derived `pageLevel` (engine.scroll, morph.tween), groups CG1-CG5
  (renamed from the Lego note's G1-G5 because G1-G4 are goals), premise `declared-rows-unverified`.
- §10.7 waves 1 and 2, CI review (no workflow change; `counts-only` rescoped), speed review, budget, cuts.
- §11 R38-R40; R2/R5/R17/R35/R37 retired. App A: A1-A28 one paragraph, A29-A40 table. App D: rev 11 log and the
  `contract-lean` review-loop record (2 refusals, Fable retro, split, final design round).

**Verified.** Theorem names and line cites read from `lean/Fw/Engine/Compose.lean` and `lean/Fw/Parts/Contract.lean`
at 16207afb; numbers from the Lego, CI, speed and model-checks notes and work-graph `evidence` fields.

**Open.**
- Length about 1,340 lines, about 40 over the ~1,300 target; next cuts: §8.2 roster, §12.0 older rows, §4.2.
- The bridge `Independent → Indep` (contract to `lego_swap_sound`) has no work-graph task; §4.8 names it as a gap.
- `contract-rows-from-code` pending: until it lands every result using the contract carries the premise.
- C3 facts (wave results, gates, `v2-proved` set) go in rev 12.

**Conventions.** Edit PLAN by scratch python scripts with exact-match asserts (the worktree guard blocks compound
shell); no new label prefix without a glossary row; contradictions go to App A with "which way and why".

**Read first.** PLAN §0, §4.8, §6.8, §10.7, App D rev 11; `research/notes/2026/10-19-lego-parts-plan.md`.
