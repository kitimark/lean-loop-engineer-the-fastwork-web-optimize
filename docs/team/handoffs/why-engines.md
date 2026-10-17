# why-engines handoff

**State:** branch worktree-agent-a65193559755a92f4 (base main 2a3bc0d); see `git log -1` there. 14 of 17 engine missingWhy statements closed in Lean (6 leave a parts-level remainder), 2 partly (n=13 WebKit half, n=25 implication), 1 open (n=17b); `sh lean/scripts/check.sh` green.
**Read first:** the "Engine mechanisms (why-engines)" sections at the end of `lean/Fw/Engine/Chromium.lean` and `lean/Fw/Engine/WebKit.lean`; the `why-engines:` sentences in `research/findings/ledger.json` mechanisms.

**Conventions:** old tables, `chromium`/`webkitAt` and the golden rows are unchanged (Parts and golden depend on them). New rows live in `CrPropX`/`WkPropX` with engines `chromiumX`/`webkitX`, and the bridge theorems `chromiumX_lift`/`webkitX_lift` say that lifted old frames give equal work. Cites: Chromium @f842f52 (`B/` = third_party/blink/renderer), WebKit @862f17d, both from `.cache/upstream`. Closed ledger entries are deleted from missingWhy and their theorems added to leanFor/leanAgainst. Parts-level remainders are retargeted to `Fw.Parts.*`.

**Model mistakes found (each a ledger statement that disagreed with source) and how to catch them earlier:**
1. n=3: `hits` was not tied to pre-paint. Every elementFromPoint runs the lifecycle to kPrePaintClean (`crWorkH`). Catch: model each Work field from the engine entry point it counts, not from a trace name.
2. n=4: pointer-events fan-out counted boxes. Repaint is per painting layer (`pePaintUnits`, `nub`). Catch: follow an invalidation flag to the object that consumes it (pre-paint), not to where it is set.
3. n=8: the "ride-along" is false for document timelines. Accelerated animations tick only when their timeline updates (`wkTicks`, `time_comp_no_ride`). Catch: state the frame context of zero-cost theorems (`anim_comp_zero` had none).
4. n=10: scroll timelines do tick every update. So the golden P1 "scrollDriven RecalculateStyles = 0" and P4 "styleRecalcs = 0" rows (WebKit.lean golden) contradict source. They are predictions that were never measured on a scroll-driven fixture. Catch: a golden row needs a measured fixture or a source cite. OPEN: lead to schedule a WKTR scroll-timeline fixture and regenerate golden (packages/contracts, not in my writes).
5. n=13: a host display is not the whole backing. In steady state it paints the dirty rect and copies the rest (`displayPx`, `host_steady_le_own`). Catch: read the display path (ImageBufferSet) before assuming "repaint = backing".
6. n=17: the stack rule was over-strong. Only effects on accelerated properties (or with a motion path) block (`prevents`, `stack_free`). Catch: quote the predicate's code, not its name.
7. n=20: a size container costs style rounds, and layouts only if layout-dirty (`wkRounds`, `wkLayouts`). Catch: separate style rounds from layout passes in every interleave claim.
8. n=22: "lowers iff c in trav" is false. Only a container on a deepest chain lowers the rounds (`wkRounds_not_iff`). Catch: test an iff with a two-chain counterexample (`decide`) before stating it.
9. n=7 (re-attach full repaint) and n=24 (WebKit svg layout) were INFERRED and are now CONFIRMED. n=19 is confirmed as stated.

**Open:**
- n=17b: CA blur cost. It runs in the closed-source render server, so it needs measurement.
- n=13: the Chromium raster half.
- n=25: the premise alpha_eff = 0 => bit 17 (R6 fixture).
- n=19: the CI fixture.
- n=4/8/10/11/16/19/20: the parts bridges, now `Fw.Parts.*` entries.
- The golden P1/P4 conflict (item 4).
