# Handoff: fix-page-offset (branch worktree-agent-a946670ce44e0f9f7, CI ref ci/fix-page-offset)

Base: integrate-ports-2 (26e5f53) + fix-pain-notes (worktree-agent-ab529d4b942d003d9).

## Result
Cause: App.tsx put the morph countdown stand-in (`wrap` 32 px margin + 120 px clock) in the `<main>` flow after the hero
track; the original keeps it in the fixed nav morph panel's centre column (out of flow). Every later section sat 152 px
lower (people 1053 vs 901 at 1512x900; the task said 120, the margin adds 32). Local debug run (Chromium, 1512x900): all
five section tops now equal the original (people 901, pain 4085.2, commission 5885.2, platform 6887.2).

## Lean row
| cell | property | original value + source | cause class | fix |
|---|---|---|---|---|
| page position of people/pain/commission/platform roots | document top | people 901 = 1800 - 899; countdown is `.waitlist-closing-countdown` (mt 32) inside `.start-selling-morph-center` (absolute, in the fixed nav panel) | extra in-flow element (placeholder wiring) | `Gate.PageOffset.flow_shift` / `outOfFlow_noShift`; App.tsx passes MorphCountdown as MorphPanel's `countdown` slot; `.countdown` slot is `display: contents` (it doubled the 32 px margin) |

## Gate gap (proposal, not wired)
lean/Fw/Gate/PageOffset.lean: cell per part = |top_ours - top_orig| <= tau (document coordinates, missing box fails).
Theorems: `pageCells_self`, `pageCells_shift_all_fail`, `shift_fails_some` (a uniform offset > tau fails a cell),
`missing_fails`. integrate-ports wires it: collect each part root's `rect.top + scrollY` in page.mjs, one cell per part.

## Changed
apps/site/src/App.tsx, apps/site/src/parts/morph.panel/morph.module.css, lean/Fw/Gate/PageOffset.lean, lean/Fw.lean.
No golden changed (wiring only; site tests 5024 pass; `lean Fw/Gate/PageOffset.lean` clean, lake build not run: main build busy).

## Open
Original centre column title wraps to 2 lines (placeholder text), so panel height differs; not a flow issue.

## CI (2 of 3 runs; dispatch breakpoint-gate parts=morph.panel,morph.countdown,pain.notes, both engines)
- 39084461260 (slot `display: contents`): morph.panel FAIL on countdown display (flex vs contents); morph.countdown pass.
- 39086309620 (slot kept, wrap margin 0 inside it; the committed state): morph.panel pass; morph.countdown FAIL on wrap
  margin-top (orig 32, ours 0). Both parts compare the SAME original element (.waitlist-closing-countdown), so one
  margin cannot satisfy both cells without doubling. Lead decision: map one role (suggest morph.countdown compares the
  slot, or the panel gate skips the slot box). Layout itself is correct (page tops equal locally).
- pain.notes sweep still FAIL 25/57 (note x 249.7 vs 308.2 at #3 @1279, 135 probes) on both runs: NOT the 16-probe state
  fix-pain-notes reported; not read further (budget). Check that integrate-ports-2 carries scene.ts correctly.
- `fw land --dry`: REFUSED scope: App.tsx and lean/Fw.lean are outside the task glob (plus integrate-ports-2's files).
