# End-of-page columns and the morph.geom flip: probe plan

Read-only investigation 2026-10-27 after the user's phone review of ?fw=morph.geom:on,morph.tween:geom-timed (ledger userDecision on
morph.tween:geom-timed). Three investigators plus a synthesis; every run named here was a local debug run, not a result.

PLAN: morph.geom / geom-timed look bugs and the cost of the end-of-page columns (lead, 2026-10-27)
Sources: 3 read-only investigators (I1 nav and flip, I2 column cost, I3 column optimizations). I re-checked the geom.css, tree.ts and geom-timed.driver.ts line numbers on main d6794ad9b. All runs below are local debug runs, so none of them is a result.

(A) Look bugs. Bugs 1-3 all come from the morph.geom flip, so they also show with morph.geom:on alone (I1 MEASURED local).
A1 One column: wrapBackdrop moves the columns into Ub, which has no flex row, so they stack at full width. CONFIRMED tree.ts:39-47 and geom.css:82-89 (I2 and I3 cite lines that are off by 5; I1's lines are right). Fix: geom.css `[data-mg=Kb],[data-mg=Ub]{display:flex;gap:inherit}`. All three investigators agree.
A2 Veil missing, so the pictures look too bright. CONFIRMED geom.css:90-93: D paints under the images, so folding the veil into D was a false premise. MEASURED local: m=1 differs from base on 8.8-11.7% of pixels, 0.04-0.13% with the veil back. Fix: restore the veil track. That means reverting the site part of 6b376eba6 (tracks.ts, tree.ts TAGS, geom.css) plus the Lean anims, MorphGeomCounts and golden rows. Close the fold premise as a finding. I3 missed this, so I3's claim that P0 alone gives E (same look) is wrong. I believe I1, who measured it.
A3 Nav button wrong / lifts:
  (a) enter() and leave() re-parent the nav children, which restarts earn-unmask, earn-sheen and the marquee. CONFIRMED tree.ts append calls; MEASURED local.
  (b) earn sits 8 px too high: the base transform stays on under `--morph:1` and the track adds its own -8 px. CONFIRMED nav.module.css:168,178 and geom.css:65.
  (c) phone action buttons sit 6 px too high: geom.css:95 hardcodes 24 px, but phone buttons are 36 px tall.
  Fix (b,c): geom.css `.is-flip [data-mg=earn]{transform:none}` and actions `top:0;bottom:0;translate:none`. Fix (a): persistent wrappers (A3a/P4), or save and restore animation currentTime as a stop-gap.
A4 Nav resize glitch: leave() removes .is-flip after is-morphing is already off, so the nav's width transition (0.68 s) and background transition (0.7 s) fire after the close. CONFIRMED tree.ts leave(), nav.module.css:41-48. Fix: in tree.ts leave(), set transition none, remove the class, flush style, then restore.
A5 "Sometimes valid and laggy": take() is decided once, at push start, by is-on-dark (geom-timed.driver.ts:63). When the hit test says light, the whole push and the pull-out after it run the faithful per-frame path. That is the valid-looking, laggy display. CONFIRMED in code; MEASURED local (Chromium 390: 3/3 pushes fell back). Fix: allow to<from; while pending, retry startTimed every frame until is-on-dark (m>0.2), with start time = st.start.
  Also open: settle(m>0) drops the tracks without goal rules (driver.ts:83-86). This is INFERRED (I3) and should be checked in the A-fix gate.
Consequence: the r2 geom/geom-timed phone rows (style 1094 / paint 9324) mix flip pushes, which showed the 1-column bug, with fallback pushes. INFERRED. They are not a clean reading; re-run after the fixes.

(B) Column cost
Base path, local Chromium: columns are 12% of main+raster at 390, 25% at 1280. Raster dominates (raster -35% / -56% with columns hidden). With the drift off, cost equals columns hidden at 390. Cause: the column width moves every frame, so each track layer is re-rastered. MEASURED local (I2); I3's fixture agrees (RasterTask 540 to 0).
Geom path with columns fixed: +5% main, no raster cost. Geom itself is -34% / -43% main+raster against base. MEASURED local.
WebKit: per-frame repaint of the tiled track layers, plus possible re-decode on reopen. INFERRED, not measured.
  I2 and I3 disagree on decode. I3 says at most 2 decodes (CONFIRMED source). I2 says there is a drop and re-decode risk after the panel is hidden. I lean to I3 for per-frame decode. I2's drop-on-hide is still open and needs a Safari probe.
User's hypothesis:
  - Partly true for the base path: the columns are a real raster share there.
  - False as an explanation of the smooth bug state: the smoothness came from the flip (no layout per frame), not from 1 column. Fixed vs bug costs are equal on the main thread. MEASURED local Chromium only.
  - Render-server and GPU cost of 5 visible column layers on iPhone/Safari is UNMEASURED and could still matter.

(C) Same-look optimizations, ranked. Prerequisites: A1+A2 and P1. Measure every one on Chromium CI (swipe-touch-v1, RasterTask and render passes), the WebKit Sim push lane (layerCount, backing MB, Paint), the iPhone push lane (Serious; p95/p99/max) and Safari macOS (xctrace hitches).
P1 Probe first (S): add a probe-only flag that sets column img visibility:hidden. Arms: base, base+off, timed-fixed, timed-fixed+off. Log per push whether the flip ran and is-on-dark at push time. Lean: arm/pushLabel rows only (Fw.Device). This decides how much P2-P5 can win at all.
1. P2 leaf opacity (S): move the backdrop's 0.4 opacity onto the leaves (tracks/images or scalers). This removes the group offscreen pass on every drift frame, including at rest. Lean: source-over lemma for disjoint coverages, with gaps 8/12 px and 12s>=8.4 > 2/dpr spill, error <= 1 LSB. The gain is render-side only (CONFIRMED Chromium property_tree_manager.cc:408-416@f842f52; INFERRED WebKit).
2. P3 column scaler (S-M): one scale(s) per column instead of 21 per-image tracks (13 on phone). Lean: identity (x, Yj+(s-1)Yj+s*y) = s*(x, Yj+y), with radius and gap scaling the same, generated from the same s(m) knots. The raster path changes (Q against geom), so add a look report at m in {0,.25,.5,.75,1}.
3. P4 static backdrop wrappers (M): put Kb>Ub permanently in the morph.panel markup, which also makes A1 structural, and later the K0..U nav wrap, which also fixes A3a. Lean: generate the wrapper markup from the Fw.Parts.MorphGeom layer tree; rest-rect equality is already gate-checked. Measure the first 3 frames and first-frame Layout/Style after push start.
4. P5 hide always-clipped pictures (S): 2/13 at 390, 4/21 at 1440. Lean: interval disjointness for all m, drift in [-56,56], s in [a,1]; the predicate is linear in vh and is generated as a golden. Small gain: run it in the same arm as P3.
5. P6 crop-reveal at <=600 px, base path only (M): local raster 540 to 0. It is Q, not E: up to 37/255 at m=1 (I3 MEASURED local). Lean: cover lemma (cw*ih <= h*iw gives a constant scale and a centre crop) plus a <=1 device px snap bound. Rank after P1: if A5 makes every push take the flip, the base path rarely runs. Present Q to the user as a look-class step.
Dropped: P7 (--morph stop at stage, tiny); drift pause during push (I2 proposes, I3 rejects as a look change with no main-thread gain; I side with I3, ledger n25); decode-at-size, contain, one shared layer, pre-composited images (ledger n14).

(D) Work-graph tasks
geom-flip-fix | part-builder | deps none | A1+A3b,c+A4 CSS and leave() flush; add a flip-state column/nav rect cell to the gate | apps/site/src/parts/morph.geom/{geom.css,tree.ts}, lean/Fw/Parts/MorphGeom{Rect,Look}.lean, lean/golden/**
geom-veil-restore | lean-prover then part-builder | deps geom-flip-fix | restore the veil track and Lean rows; close the fold premise | lean/Fw/Parts/MorphGeom{,Anim,Counts,Gen}.lean, apps/site/src/parts/morph.geom/{tracks.ts,tree.ts,geom.css}, research/notes/2026/10-2x-morph-geom.md
timed-take-retry | lean-prover then part-builder | deps none | Lean take guard (allow to<from, retry while pending) with a continuity proof; driver change | lean/Fw/Parts/MorphGeomTimed{,Gen}.lean, apps/site/src/parts/morph.tween/{geom-timed.driver.ts,driver.ts}
flip-anim-keep | part-builder | deps geom-flip-fix | keep CSS animation time across re-parenting (stop-gap until P4) | apps/site/src/parts/morph.geom/tree.ts (runs serially with geom-flip-fix: same file)
cols-probe | measure-engineer | deps geom-flip-fix, geom-veil-restore, timed-take-retry | P1 probe flag plus per-push flip log on all 4 environments; re-run phone r2 arms | apps/site/src/parts/morph.columns/probe*, packages/measure*/**, research/notes/2026/10-27-cols-probe.md
cols-leaf-opacity | lean-prover then part-builder | deps cols-probe | P2 | lean/Fw/Parts/MorphLeafOpacity.lean, apps/site/src/parts/morph.{panel,columns}/*.css
cols-scaler | lean-prover then part-builder | deps cols-probe, geom-veil-restore | P3 (+P5 in the same arm) | lean/Fw/Parts/MorphGeom{Anim,Gen,Clip}.lean, apps/site/src/parts/morph.{geom,columns}/**
backdrop-static-wrap | part-builder | deps cols-scaler | P4 | apps/site/src/parts/morph.{panel,geom}/**, lean/Fw/Parts/MorphGeom.lean
cols-crop-reveal | lean-prover then part-builder | deps cols-probe result showing base-path pushes still common | P6, look-class Q, user review | lean/Fw/Parts/MorphColumnsCrop.lean, apps/site/src/parts/morph.columns/**
Open questions:
- Why the hit test reads light at 390 in Chromium but dark at the exact bottom in WebKit.
- Whether WebKit uses group opacity (allowsGroupOpacity): check with Instruments offscreen-rendered layers on Safari macOS.
