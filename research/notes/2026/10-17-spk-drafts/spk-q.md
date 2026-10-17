---
id: 2026-10-17-spk-q
kind: note
title: "SPK-q: do N0/N1 read 0 on arm A (the original) in W-rest and W-measure, in both engines?"
status: draft
created: 2026-10-17
topics: [spike, decision-record, styling-neutrality, n0, n1, counts-lane]
---

# SPK-q (DRAFT decision record)

**Question (PLAN Appendix B).** Styling-neutrality baseline: do N0/N1 read 0 on arm A in W-rest and W-measure, in both
engines?

**Status: OPEN.** Expected 0 from a grep of the original's JS; the lanes do not yet record N0 or N1.

## Evidence
| Claim | Evidence | Status |
|---|---|---|
| The original's JS has no runtime CSS-in-JS (no Emotion/styled-components insertion path), so sheet mutations after load are expected 0 | `research/kickoff/09-mui-zero-runtime/03-measurement-impact.md` §4, §6 | CONFIRMED (grep, per PLAN) |
| N0 = page-side census (CSSOM write wrappers + `MutationObserver` on `<style>`/`<link>`); N1 = engine side (`StyleEngine::updateActiveStyleSheets`, `scheduleInvalidationsForRuleSets`, font-update slices) | PLAN §4.2 line ~382; `03-measurement-impact.md` line ~231 | CONFIRMED (spec) |
| The Chromium lane's count types do not include an N0 census or the N1 slices | `packages/measure-chromium/README.md` "Count types" @ddc91b2 | CONFIRMED |
| The WebKit lane records `RecalculateStyles` and `ScheduleStyleRecalculation` totals (stable) but no sheet-mutation census | `packages/measure-webkit/README.md` @ddc91b2 | CONFIRMED |
| Indirect: style-recalc counts are non-zero during the scripted swipe (deterministic `RecalcStyleCount`, stable `RecalculateStyles`), so they cannot stand in for N1 | READMEs | MEASURED |
| The site side has an N0 census for arm B (SPK-r, Chromium half pass: `aot` 0 CSSOM insertions, `runtime` control caught) | `apps/site/README.md` @d380999 | MEASURED (arm B only) |

**Evidence commit:** `d380999` (arm-B census), `ddc91b2` (lane READMEs); HEAD `30e3264`.

## Missing
- N0 census injected into the counts lanes (page-side wrappers before any page script; the clock shim is the model).
- N1 trace slices on the pinned Chromium build; this needs SPK-h (do the slices exist, what does `blink_style` cost).
- WebKit N1 (Inspector `Timeline` style records already exist; whether they separate sheet updates is untested).
- Note: PLAN lists SPK-q in the M0 gate row (line ~1237) and in the M1 row (line ~1238, "N0/N1 read 0 on arm A"). The
  lane work for it is M1 work. **Lead to decide:** keep SPK-q in M0 as "grep-confirmed expectation, recorded open", or
  move it to M1.

## Next step
1. SPK-h first (trace args and N1 slices on the pinned build). Owner: measure-engineer (meas-chromium-2); research
   questions to the researcher.
2. Add N0 census and N1 slices to both lanes, then run W-rest and W-measure on arm A. Owner: measure-engineer
   (meas-chromium-2, meas-webkit-2).
3. Record the zero (or the incident) here. Owner: measure-engineer.

## What this changes in the plan
- §10.2: SPK-q is not answerable at M0 without lane changes; either move it to M1 or accept the grep as the M0 answer
  and mark it "open (expected 0)". Appendix B: no status change.
