---
id: 2026-10-20-commission-margin-recur
kind: note
title: "Commission margin-inline gate readings fail intermittently: round 1 evidence"
status: draft
created: 2026-10-20
topics: [gate, chromium, commission, content-visibility, settle]
---

# Commission margin-inline readings: what round 1 measured

Status of every claim in the sections up to "Round 2 plan": MEASURED as stated, with the cause line INFERRED. Round 2 (below) confirms or
corrects them.

## Answer

- The failures are one reading per failing run: the first stop (stop 0, no resize yet) of one sweep, on the commission
  `inner` and `rows` boxes. The used auto `margin-inline-start/-end` of the original arm reads `0px`; the rewrite arm reads
  the steady value (`96px`/`132px` for inner, `8px` for rows). Every later reading of the sweep, after a resize, is fresh
  (MEASURED, five artifacts below).
- Both arms can be stale in the same run: in run 39314718340 the `pain-1440-600-1440` stop 0 reads `0px` on both arms
  (expected 96px/8px), so it passes by agreement, not by being right (MEASURED, `inner.items[0].style` of stop 0).
- The CSS rules and rects of orig and rewrite are identical at the failing stops; only the used margin differs
  (MEASURED: a deep diff of `parts.commission` of orig vs rewrite, `declared` lists excluded, shows only the four margin keys).
- Cause hypothesis (INFERRED): stop 0 reads the used margin of a box inside a `content-visibility:auto` subtree that is
  still skipped, before any layout pass has included the box (a later resize forces one). Round 2 tests it.

## The five round-1 runs (workflow breakpoint-gate, chromium 156.0.8078.4, runner ubuntu-24.04-arm)

| local id | run | branch | flags | commission |
| --- | --- | --- | --- | --- |
| r1 | 39313815482 | ci/countdown-one-chain | `hero.countdown:one-chain` | fail |
| r2 | 39314391342 | ci/exit-scoped-var | `hero.exit:scoped` | fail |
| r3 | 39314718340 | ci/ci-telemetry | none | fail |
| r4 | 39312308450 | ci/morph-layers | `morph.mount:shift-dormant` | pass |
| r5 | 39282664077 | ci/c3-gate | `preset=v2-proved` | pass |

The runner host name is not stored in the artifact (the chromium gate writes no `runner.json`); shard job ids and times
come from `gh run view --json jobs`.

## The failing readings (MEASURED, chromium.json `sweeps[].orig/rewrite[0].parts.commission`)

| run | reading id | stop | viewport | key | orig | rewrite | shard job (start-end UTC) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 39313815482 | pain-1440-600-1440#0 | 0 | 1440 | inner margin-inline-start/end | 0px | 96px | chromium j1, 118270614599 (19:48:44-20:01:19) |
| 39313815482 | pain-1440-600-1440#0 | 0 | 1440 | rows margin-inline-start/end | 0px | 8px | same |
| 39314391342 | pain-1440-600-1440#0 | 0 | 1440 | inner margin-inline-start/end | 0px | 96px | chromium j1, 118273411217 (19:56:47-20:09:26) |
| 39314391342 | pain-1440-600-1440#0 | 0 | 1440 | rows margin-inline-start/end | 0px | 8px | same |
| 39314718340 | desktop-1512-320-1512#0 | 0 | 1512 | inner margin-inline-start/end | 0px | 132px | chromium j0, 118274997440 (20:02:01-20:14:20) |
| 39314718340 | desktop-1512-320-1512#0 | 0 | 1512 | rows margin-inline-start/end | 0px | 8px | same |

- Shard of the failing sweep: from the three shard files of run 39314718340 (desktop on j0, pain on j1, phone and touch on
  j2). The shard of the same sweep in the other two runs is INFERRED by the same assignment.
- Settle of the failing stop: both arms `settled@2`, 192 ms waited, 3 frames, parked, no running animation (MEASURED).
- Same stop in the passing runs and the other arm: orig reads 132px (r1, r2 desktop stop 0) or 96px, so the box can read
  fresh at stop 0; the failure is intermittent per run and per arm.
- Readings of the same sweep after stop 0 (orig, inner margin-inline-start): desktop 132, 131.5, 16, 15.5, 0, 0 px...;
  pain 0 (stale), 0 (600px, legitimate), 96, 0, 96 px. The narrow phone and touch sweeps read 0px on every stop and both
  arms (legitimate, the box has no auto margin there).
- Timing: the stale reading has no time axis in the artifact (one reading per stop); it is the first read after the
  page-ready wait of the sweep.

## Round 2: the diagnostic (run 39333030506, chromium 156.0.8078.4, parts=commission)

Run 39324419271 (diag v1) hung: the frozen page clock never advanced for a resize without `holdTo`, the job hit its 60 min cap.
Diag v2 (branch ci/cmr-diag2) loads 2 widths (1440, 1512) x 12 loads x 2 arms = 96 loads per arm with the sweep's own load,
ready, settle and collect calls, writes one `DIAGCV` line per load, then resizes by one CSS pixel and back (MEASURED, 192 loads,
0 errors; the logs are the run's three shard logs).

| arm | stale `0px` at the sweep's own collect | of | the same loads after the 1 px wiggle |
| --- | --- | --- | --- |
| original | 21 | 96 | fresh (96/96 loads) |
| rewrite | 1 | 96 | fresh (96/96 loads) |

- The stale value persists across repeated forced reads inside one load: in the 9 stale loads that snapshot before the collect,
  `ready`, `settled`, `again` (a second style read) and `afterCollect` all read `0px` (MEASURED). A rect read between them does
  not fix it: the rect is the correct one and the margin derived from the geometry (left of the box minus left of its parent minus
  the parent padding) is the steady 96/132 px while the style read says `0px` (MEASURED).
- After the resize to width+1 every one of the 22 stale loads reads the steady value, and again after the resize back
  (`wig+1`, `wigback`, MEASURED). Hypothesis (b) of round 1 holds: the stale `0px` is a used auto margin read before a committed
  layout pass has included the box, it is not the rule or the rect.
- The staleness is a property of the page, not of the gate order: it appears in both snapshot variants (collect first, snapshot
  first), at both widths, and the original shows it far more often than the rewrite (21 against 1).

### Why Blink returns 0 there (CONFIRMED read path, INFERRED trigger)

Source at `.cache/upstream/chromium@f842f52` (f842f52ef39fd97b449eb27cff414bf05a98ddce) and the same sha fetched for the
generated property file:

- `getComputedStyle` of a margin whose specified value is not fixed (`auto`) is a layout-dependent read. It returns
  `box->MarginOutsets().left` (`third_party/blink/renderer/core/css/properties/longhands/longhands_custom.cc:6936-6941@f842f52`,
  `MarginLeft::CSSValueFromComputedStyleInternal`; the logical inline start/end go through the same box accessors).
- `LayoutBox::MarginOutsets()` returns the first physical fragment's `Margins()` and a zero strut when the box has no
  fragment (`third_party/blink/renderer/core/layout/layout_box.cc:1059-1067@f842f52`); `PhysicalBoxFragment::Margins()` is the
  rare field `kMargins` or a zero strut when the field was never written (`.../physical_box_fragment.h:274-279@f842f52`).
- The field is written by the container's layout, not by the box's own: `BoxFragmentBuilder::AddResult` calls
  `SetMargins(...)` on the child fragment when it adds the child (`.../box_fragment_builder.cc:219-224@f842f52`), and
  `BlockNode::UpdateMarginPaddingInfoIfNeeded` sets the style-resolved margins for the paths that skip `AddResult`
  (`.../block_node.cc:1526-1540@f842f52`, its own comment: "This margin data may be overwritten by BoxFragmentBuilder::AddResult()").
  So a used auto margin is layout output of the parent's pass; it is not computed from style at read time.
- The commission section is a `content-visibility:auto` subtree that is skipped while off screen. A forced style and layout
  update (the `getComputedStyle` path, `doc.UpdateStyleAndLayoutForNode`,
  `.../css/css_computed_style_declaration.cc:327@f842f52`) lays out a locked subtree only as far as the lock allows; INFERRED
  trigger: the box then has a fragment whose `kMargins` was never written by a container pass that knew the final available
  width, so the read returns the zero strut. The mechanism of the missing write is not shown by the diag; the effect and the
  cure (a viewport resize, which invalidates and re-lays out the document) are MEASURED.

## The fix (rule in Lean, then code)

Rule (`lean/Fw/Gate/Settle.lean`, section "a layout-output value is read only after a committed layout pass"): a read of a
layout-output value (a used auto margin) is kept only when a committed layout pass preceded it (`committed viewed resizes`:
the view path, or at least one resize of the arm). Otherwise the wait is `unsettled` (`commitOutcome`), never a pass or a fail.
A fresh load that the gate reads without the view bring is opened one CSS pixel wider (`nudge`, checked not to cross a
breakpoint edge, `crosses_iff`) and resized to the read width, so it behaves as every later stop of a sweep does.

- `layoutCell_fail_of_steady_diff`: committed reads, both settled, steady values differ: `fail`, whatever the stale values are
  (equal stale values cannot hide a real original/rewrite difference).
- `layoutCell_uncommitted_never_pass`, `layoutCell_uncommitted_unsettled`: an uncommitted read in either arm is never a pass and
  never a fail, also when both arms are stale and equal (run 39314718340 passed `pain-1440` by that agreement before).
- `layoutCell_pass_sound`: a pass needs both reads committed, equal steady values, both arms settled.
- `layoutCell_committed`: with every read committed the cell is the plain settle cell on the steady values (the rule is inert).
- `commitHolds_webkit_default`: WebKit is not changed (it does not bring parts either; no stale used margin was seen there).
  Accepted limit: the rule is applied where the engine brings parts (Chromium), by the `viewFor` flag.
- Scope in the gate: sweep stop 0 (the first read after a load) and the fresh load after each sweep (the hysteresis pair; its
  orig counts 9 against 5 in runs 39313815482 and 39314718340 were the same stale margin, four keys) in Chromium. The probes
  in Chromium are on the view path already (`viewed`).

