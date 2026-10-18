# Handoff: fix-nav-hittest

Branch `worktree-agent-a16d8427e05d92cb3` (CI ref `ci/fix-nav-hittest`). No source change: the cell was already fixed by the base.

## Lean row
| field | value |
|---|---|
| cell | nav.hitTest style, `nav` element, border-{top,right,bottom,left}-color, all 488 Chromium / 472 WebKit probes |
| property | computed border colour (width 0px, style none, unchanged: only the colour differed) |
| original value | rgb(23, 23, 23) = currentcolor of the nav (`border:0` in `.start-selling-top-nav`, snapshot assets/2.gBuqKVzi.css), inheriting body colour #171717 |
| rewrite value | rgb(0, 0, 0) |
| cause class | stale build input, not a port difference: run 39080214138's site-dist (gate-settle's base) had only `body{margin:0}`, no global body colour; `border:0` resets to currentcolor, so it read the UA black |
| fix | already in the base: `styles/reset.css` body `color:#171717` (fb88aa2); no nav.module.css change (border rule identical to original), nav not touched |

## Evidence
- Local build of this head: nav computed color and border-top-color both rgb(23,23,23).
- CI breakpoint-gate dispatch 39082828467 (parts nav.hitTest,nav; both engines): success, nav.hitTest and nav pass in every column on Chromium and WebKit.
- Push runs of ci/fix-nav-hittest were cancelled (1 dispatch used of 3).

## Open
- Lean: nothing new to prove; the colour is the global base rule's (integrate-ports handoff). A Lean fact "nav border colour = body colour" would be a premise of the reset, not nav.hitTest.
