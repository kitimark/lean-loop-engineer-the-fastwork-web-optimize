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
