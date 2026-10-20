---
id: 2026-10-20-commission-margin-recur
kind: note
title: "Commission margin-inline readings fail intermittently: a used auto margin reads the zero strut in a skipped subtree"
status: finding
created: 2026-10-20
topics: [gate, chromium, commission, content-visibility, settle]
---

# Commission margin-inline readings: evidence and cause

Status words: CONFIRMED (source file:line or artifact), MEASURED (a CI run id is cited), INFERRED. All runs are workflow
breakpoint-gate on Chromium 156.0.8078.4, runner ubuntu-24.04-arm, unless a row says otherwise. No code from this task is
kept; the note closes the task as a finding and names the follow-up tasks under "Next".

## Answer

- Cause line: read path CONFIRMED (Blink file:line@f842f52, below), trigger INFERRED.
- Six failing readings in 3 of the 5 round-1 runs (two per failing run). Each is stop 0 (no resize yet) of one sweep, on the
  commission `inner` box and the `rows` box. The used auto `margin-inline-start/-end` of the original arm reads `0px`; the
  rewrite arm reads the steady value (`96px`/`132px` for inner, `8px` for rows). Every later reading of the sweep, after a
  resize, is fresh (MEASURED, table below).
- Both arms can be stale in the same run. In run 39314718340 the `pain-1440-600-1440` stop 0 reads `0px` on both arms
  (expected 96px/8px), so it passes by agreement and not by being right (MEASURED, `inner.items[0].style` of stop 0).
- The CSS rules and rects of orig and rewrite are identical at the failing stops; only the used margin differs (MEASURED, a deep
  diff of `parts.commission` of orig against rewrite with `declared` lists excluded shows only the four margin keys).
- The stale `0px` is a used auto margin read from a box whose container pass never wrote it. The rect is right while the style read
  is wrong (MEASURED, diag v2 and v3b).
- A 1 px resize cures `inner` (22 of 22 stale loads in diag v2) but not `rows` (22 of 22 stale loads still read `0px`, diag v2 and
  v3b). A viewport change is no general cure, and no gate-side cure was found (MEASURED).

## The five round-1 runs

| local id | run | branch | flags | commission |
| --- | --- | --- | --- | --- |
| r1 | 39313815482 | ci/countdown-one-chain | `hero.countdown:one-chain` | fail |
| r2 | 39314391342 | ci/exit-scoped-var | `hero.exit:scoped` | fail |
| r3 | 39314718340 | ci/ci-telemetry | none | fail |
| r4 | 39312308450 | ci/morph-layers | `morph.mount:shift-dormant` | pass |
| r5 | 39282664077 | ci/c3-gate | `preset=v2-proved` | pass |

The runner host name is not stored in the artifact (the chromium gate writes no `runner.json`); shard job ids and times come
from `gh run view --json jobs`.

## The failing readings (MEASURED, chromium.json `sweeps[].orig/rewrite[0].parts.commission`)

| run | reading id | stop | viewport | key | orig | rewrite | shard job (start-end UTC) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 39313815482 | pain-1440-600-1440#0 | 0 | 1440 | inner margin-inline-start/end | 0px | 96px | chromium j1, 118270614599 (19:48:44-20:01:19) |
| 39313815482 | pain-1440-600-1440#0 | 0 | 1440 | rows margin-inline-start/end | 0px | 8px | same |
| 39314391342 | pain-1440-600-1440#0 | 0 | 1440 | inner margin-inline-start/end | 0px | 96px | chromium j1, 118273411217 (19:56:47-20:09:26) |
| 39314391342 | pain-1440-600-1440#0 | 0 | 1440 | rows margin-inline-start/end | 0px | 8px | same |
| 39314718340 | desktop-1512-320-1512#0 | 0 | 1512 | inner margin-inline-start/end | 0px | 132px | chromium j0, 118274997440 (20:02:01-20:14:20) |
| 39314718340 | desktop-1512-320-1512#0 | 0 | 1512 | rows margin-inline-start/end | 0px | 8px | same |

- Shard of the failing sweep: from the three shard files of run 39314718340 (desktop on j0, pain on j1, phone and touch on j2).
  The shard of the same sweep in the other two runs is INFERRED by the same assignment.
- Settle of the failing stop: both arms `settled@2`, 192 ms waited, 3 frames, parked, no running animation (MEASURED).
- Same stop in the passing runs and the other arm: orig reads 132px (r1, r2 desktop stop 0) or 96px, so the box can read fresh at
  stop 0; the failure is intermittent per run and per arm.
- Readings of the same sweep after stop 0 (orig, inner margin-inline-start): desktop 132, 131.5, 16, 15.5, 0, 0 px; pain 0
  (stale), 0 (600px, legitimate), 96, 0, 96 px. The narrow phone and touch sweeps read 0px on every stop and both arms
  (legitimate, the box has no auto margin there).
- The artifact has one reading per stop and no time axis; the stale reading is the first read after the page-ready wait of the
  sweep.

## Diagnostics (MEASURED)

Run 39324419271 (diag v1) hung: the frozen page clock never advanced for a resize without `holdTo`, and the job hit its 60 min
cap. The diag code lives only on `cmr-diag3` / `ci/cmr-diag3`.

Diag v2 (run 39333030506, branch ci/cmr-diag2, `parts=commission`) loads 2 widths (1440, 1512) x 12 loads x 2 arms = 96 loads
per arm, with the sweep's own load, ready, settle and collect calls. It writes one `DIAGCV` line per load (192 lines, 0 errors),
then resizes by one CSS pixel and back. Diag v2 recorded `rl` (the `rows` style) but not `rderived`; `rderived` came with diag v3
(`cmr-diag3`, 2aeb902d, e5e3791e). Counts re-read from the run log:

| arm | loads | `inner` `0px` at the sweep's own collect | `rows` `0px` at collect | `inner` after the 1 px wiggle | `rows` after the wiggle |
| --- | --- | --- | --- | --- | --- |
| original | 96 | 21 | 21 | fresh (21 of 21) | `0px` (21 of 21) |
| rewrite | 96 | 1 | 1 | fresh (1 of 1) | `0px` (1 of 1) |

So 22 of 192 loads are stale (21 original, 1 rewrite), on both boxes at once. The 21 against 1 is the `inner` and `rows`
count together at one collect; it is not an `inner`-only asymmetry.

- The stale value persists across repeated forced reads inside one load. In the 9 stale loads that snapshot before the collect
  (variant S), `ready`, `settled`, `again` (a second style read) and `afterCollect` all read `0px`.
- A rect read between them does not fix it. The rect of the box is the correct one in these 9 loads; the margin derived from the
  geometry is the steady value in rect space (below) while the style read says `0px`.
- After the resize to width+1, `inner` reads the steady value in all 22 stale loads, and again after the resize back (`wig+1`,
  `wigback`). `rows` stays `0px`.
- Staleness is a property of the page, not of the gate order: it appears in both snapshot variants (collect first, snapshot
  first) and at both widths.

Diag v3b (run 39340222228, 1008 `DIAGCV` lines, 504 loads per arm; widths 1440 and 1512, variants A to G). Per arm, over all
snapshots (variants A and B take 1 per load, C 3, G 2, D to F none):

| arm | loads | `inner` `0px` snapshots | `rows` `0px` snapshots | loads with `rows` `0px` |
| --- | --- | --- | --- | --- |
| original | 504 | 30 | 114 | 67 |
| rewrite | 504 | 7 | 22 | 16 |

- Geometry-derived margins (box left minus parent left minus parent padding-left, field `derived`/`rderived`) are 83.33 px
  at width 1440, 116.33 px at 1512 and 7.33 px for `rows`. They are the same in stale and fresh reads. They are in the card's
  scaled (rect) space, not the steady layout values: derived = (steady + p) x s - p, where s = 0.916667 is the card scale
  and p the parent padding-left (56 px for `inner`, 0 for `rows`; the snapshot CSS assets/2.gBuqKVzi.css has `padding: ... 56px ...`
  rules, which of them the parent matches is INFERRED), because the card carries
  `transform: scale(var(--commission-shrink-scale))` with `--commission-enter-shrink:1`, a scale of 1 - 0.083333 = 0.916667 above
  1000 px (CONFIRMED, snapshot `_app/immutable/assets/2.gBuqKVzi.css`, custom properties `--commission-shrink-scale` and
  `--commission-enter-shrink`). Check: 7.33 / 0.916667 = 8, and (83.33 + 56) / 0.916667 - 56 = 96.
  An earlier reading of these numbers as the steady 96/132 px was wrong.
- Diag v3 (run 39342083691): a part brought into view and then scrolled back (skipped again) reads `0px` again. The value is not
  kept; a margin in a skipped subtree is a reading only while the subtree is not skipped.
- Diag v3b: a 1 px resize cures `inner` but not `rows`; the stale `rows` margins persist across resizes and a second collect
  does not cure them.

## Why Blink returns 0 there (read path CONFIRMED, trigger INFERRED)

Source at `.cache/upstream/chromium@f842f52` (f842f52ef39fd97b449eb27cff414bf05a98ddce):

- `getComputedStyle` of a margin whose specified value is not fixed (`auto`) is a layout-dependent read. It returns
  `box->MarginOutsets().left` (`third_party/blink/renderer/core/css/properties/longhands/longhands_custom.cc:6936-6941@f842f52`,
  `MarginLeft::CSSValueFromComputedStyleInternal`; the logical inline start and end go through the same box accessors).
  `IsLayoutDependent` requires `!style->MarginLeft().IsFixed()` (same file, 6927-6945@f842f52).
- `LayoutBox::MarginOutsets()` returns the first physical fragment's `Margins()` and a zero strut when the box has no fragment
  (`third_party/blink/renderer/core/layout/layout_box.cc:1059-1067@f842f52`). `PhysicalBoxFragment::Margins()` is the rare field
  `kMargins`, or a zero strut when the field was never written (`.../physical_box_fragment.h:274-279@f842f52`).
- The field is written by the container's layout, not by the box's own. `BoxFragmentBuilder::AddResult` calls `SetMargins(...)`
  on the child fragment when it adds the child (`.../box_fragment_builder.cc:219-224@f842f52`), and
  `BlockNode::UpdateMarginPaddingInfoIfNeeded` sets the style-resolved margins for the paths that skip `AddResult`
  (`.../block_node.cc:1526-1540@f842f52`; its comment says the data may be overwritten by `BoxFragmentBuilder::AddResult()`).
  So a used auto margin is layout output of the parent's pass; it is not computed from style at read time.
- The Typed OM read `el.computedStyleMap().get(k)` calls `CSSValueFromComputedStyle` with `nullptr /* layout_object */`
  (`.../css/cssom/computed_style_property_map.cc:129-130@f842f52`), so it skips the `MarginOutsets` branch and returns the
  specified length, `auto` for an auto margin. It updates only the layout tree (line 76), not layout (CONFIRMED read path; the
  engine behaviour is not yet measured).
- The commission section is a `content-visibility:auto` subtree that is skipped while off screen. Both arms set it through a
  data attribute: the snapshot sets `data-start-selling-render=deferred` from a `deferRendering` driver (CSS
  `2.gBuqKVzi.css`, JS `nodes/2.DyWL8TcE.js`), our site sets `data-render` in
  `apps/site/src/parts/commission/driver.ts:147-158` with the rule in `apps/site/src/parts/commission/commission.module.css:24-27`.
  A forced style and layout update (the `getComputedStyle` path, `doc.UpdateStyleAndLayoutForNode`,
  `.../css/css_computed_style_declaration.cc:327@f842f52`) lays out a locked subtree only as far as the lock allows. INFERRED
  trigger: the box then has a fragment whose `kMargins` was never written by a container pass that knew the final available
  width, so the read returns the zero strut. The mechanism of the missing write is not shown by the diag. Only the effect
  (MEASURED) and the failed cures are.

## History: what was tried

- Nudged fresh load (commit 9c31df36). The design forced a committed layout pass before the first sweep read (open one CSS pixel
  wider, resize to the read width) and made an uncommitted read unsettled. Runs 39335178250, 39335168536 and 39335157627 (same
  commit, no flags): in 3 of 3 the chromium commission row failed at `desktop-1512-320-1512#0` and `pain-1440-600-1440#0` on the
  `rows` margins, original `0px` against rewrite `8px` (MEASURED). The premise that a committed layout pass cures the stale read
  fell here; it had survived diag v2, where the cure was counted on `inner` (INFERRED reason).
- Key mask (commit 22b3fd20, branch ci/cmr-fix2). A key mask was tried at 22b3fd20 (ci/cmr-fix2) and refused in review as a
  tolerance widening: it dropped every margin key of every node read in a skipped subtree from the comparison, in all 72
  Chromium sweep stops and the hysteresis pair, for every `content-visibility:auto` part and not for the commission only. Its
  proofs showed that a difference is lost only under the mask, not that a masked reading equals a steady value. The mask is not
  kept; nothing of it is on main.
- Evidence kept from the key-mask proof runs (commit 22b3fd20, no flags, `engines=both runs=3`), as run ids only. Chromium
  commission row pass in 39344334974, 39344352614 and 39350369366; 39344343539 lost a WebKit runner (infra, no verdict). Flagged
  heads, `engines=chromium parts=commission`: 39344441533 (ci/cmr-fix2-esv), 39344450727 (ci/cmr-fix2-ml), 39344459695
  (ci/cmr-fix2-cdc), commission row pass. These passes say the comparison stopped looking at the margins; they do not say the
  readings became right.
- WebKit: the proof runs show a commission pass in the WebKit column, and the engine verdict "incomplete" from
  `matchMedia =Lean|sweep:phone-rotation` (not comparable). The WebKit commission columns and their UNREACHABLE cells are
  unverified here: no main-branch run id is cited, and the reach rule is INFERRED to predate this task (it appears in the
  notes notes-scroll-idem and gate-page-root-anchor). All six failing readings above are Chromium readings.

## Next

Three tasks, in this order of dependency (the first is the premise task for the second).

- `cmr-margin-typed-om`: premise task. Pin on CI that `computedStyleMap().get('margin-inline-start')` returns `auto` for the
  commission boxes in a skipped subtree while `getComputedStyle` returns the strut (read path above, CONFIRMED; engine
  behaviour unmeasured). Assert only what is stable: the stale `0px` is intermittent (21 of 96 original loads, 1 of 96
  rewrite), so a premise test must not assert style = `0px`.
- `cmr-margin-rect-rule`: a rect-verdict rule for an inline margin that is non-fixed in both arms. The margin is judged by the
  box rect, not the style string. Constraints from the adversarial check: the geometry is in the scaled rect space
  (divide by the product of the shared transform scales of the parent, 0.916667 for the card; golden rows 83.33 + 56 to 96 and
  7.33 to 8); the remainder equals the start margin only for a block child in block flow or an item of a column-flex container
  (commission `inner` and `rows` are column-flex items) in LTR horizontal-tb, so the rule needs the parent's display,
  flex-direction, writing-mode and direction as read inputs and keeps the style read when they fail; the rule names its Lean
  definition and compares exactly after snapping to 1/64 px in both arms; sweeps and the fresh hysteresis sample must read the
  inputs (main has no flag read in sweeps), or the rule drops the flag and reads every non-fixed inline margin; its evidence
  must show at least one reading where the style was the strut and the rect-verdict value equalled the other arm's, else it
  reports "rule not exercised". Three passes alone show little: round 1 failed 3 of 5 runs, so three passes in a row occur by
  chance about 6% of the time.
- `cmr-strut-asym`: investigation, no gate change. Why the original reads the strut in 21 of 96 loads against 1 of 96 for the
  rewrite (v2, both boxes), and 114 against 22 `rows` snapshots in v3b, and why `rows` survives a resize while `inner` does not.
  Both arms set `content-visibility:auto` on the section through the same deferral pattern, so the lock boundary is equal.
  Candidates: when the attribute lands relative to the first layout, and the intrinsic-block-size measure. Stays INFERRED until
  measured.
