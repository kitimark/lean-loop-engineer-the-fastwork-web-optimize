---
id: people-title-crash-fix
kind: note
title: "The people title no longer crashes stock Chrome with the flag people.o:title-wrap; the block o does not fix it"
status: draft
created: 2026-10-23
topics: [chromium, crash, text-wrap, people, flags]
---

# People title crash fix

Task `people-title-crash-fix`, after `chrome-balance-repro` (`10-2x-chrome-balance-repro.md`, run 39878812594).

## Answer

- MEASURED: the option the task preferred, the `o` as a block with its declared width (`people.o:block`, Lean
  `Fw.Parts.PeopleOBlock`: same box, stage, transition, line box and position), does NOT stop the crash. Run 39889621434
  (flag on) and 39889660302 (control) have identical rows: every page variant above 860 px crashes in Chrome for Testing
  156.0.8078.4, 156.0.8078.47, 157.0.8103.15 and 158.0.8118.0 (SIGSEGV `SEGV_MAPERR 0x84`), and so does the minimal title with
  the block `o` at `width: .6042em` (`cft4-min-blockw`). The earlier "inline-block is ok" row had width 0 (the grid columns are
  ignored, so `width: auto` is 0): a different look, not the same one.
- MEASURED bisect (run 39890158715, stock 156.0.8078.4, rewrite page at 1280, css injected): crashes with the block `o` at any
  width above zero (`.6042em`, `1px`; also with `overflow: visible`, `position: static`, `height: auto`/`0`), with
  `contain: layout`, `contain: size layout`, `position: static`, `overflow: visible`, `height: auto`, `vertical-align: top`, an
  `inline-block` word, an absolute or hidden stage. No crash with `#future-heading{text-wrap: wrap}`, and with three CSS changes
  that move the `o` out of the line or give it no width (`display: inline-block` bare, `inline-block; width: 0`,
  `position: absolute`), which change the look. So the only fix with the same look is the title's `text-wrap`.
- MEASURED with the fix in the page (run 39891744638, two runs, shipped CSS with the wrap applied): no crash at 861, 1100,
  1280 and 1440 px in Chrome for Testing 156.0.8078.4, 156.0.8078.47, 157.0.8103.15 and 158.0.8118.0, and none at 860 and 390 px;
  the minimal title page with the block `o` (`cft4-min-blockw`) crashes in the same run, so the harness still detects it.
- PROVED (Lean `Fw.Parts.PeopleTitleWrap`): above 860 px the title fits one line (`fits_one_line`: `12 em * fontPx <= vw - sb - 112`
  with a scrollbar of up to 40 px; narrowest case `432 px` of `709 px`), and two line breakers that place no break when everything
  fits agree (`same_when_fits`). Balancing returns at once for one line (`score_line_breaker.cc:139-142`,
  `paragraph_line_breaker.cc:210`@f842f52). So `wrap` and `balance` give the same lines for the title at 861 to 1440 px and beyond.
  At 860 px and below the title already has `text-wrap: unset` and a flex column (never balanced), which is why 860 px did not crash.
- Decision: a flag, `people.o:title-wrap`, and the faithful default keeps `balance`. Reason: the breakpoint gate reads the
  title's `text-wrap-style`. With the change as the default, run 39891679733 failed 111 readings on Chromium and 105 on WebKit,
  every one `balance` against `auto` on the title at widths above 860 px, and nothing else. A default change would turn the gate red.
  The flag is exclusive with `preview-translate` (one variant per part); a combined variant is a follow-up. The desktop counts lanes need
  `--fw people.o:title-wrap`.
- Real desktop Chrome: the original site's crash is Fastwork's to fix; we report it only (see the prior note for the report text).

## Gate and pixels

- Gate, both engines, the change as default (run 39891679733, tip b3a92c3): only the title's `text-wrap-style` differs
  (Chromium 111 fail, WebKit 105 fail, all others pass); the same CSS is what the flag applies.
- Gate, `people.o:block` (run 39889281962): `people.o` fails 30/30 on `display` (grid against block), `grid-template-columns`
  and `transition-property`; people.card passes. That option is refuted anyway.
- Trajectory probe, default config, tip b3a92c3: run 39891679693 pass.
- Pixels: the CI visual-diff push run (39891679931) has `people.card` at desk-861 and desk-1100 `unsettled` on both engines
  (the whole card is still moving in that run), so it holds no pixel verdict; the restricted base dispatch (39891109938, WebKit,
  people.card at 861 and 1100) was settled but has no matching fix dispatch (the 6-dispatch cap was spent). Local debug only,
  not a result: Playwright WebKit on this Mac, base against `?fw=people.o:title-wrap`, the title box at 861, 1100, 1280 and
  1440 px: 0 changed pixels closed and the same `o` rect; the opened row differs by the same order as base against base (faces
  region only), the title text region is identical. The CI pixel compare is a `dispatch` item for the lead.

## What changed

- `lean/Fw/Parts/PeopleTitleWrap.lean`, `PeopleOBlock.lean` (marked refuted).
- `apps/site/src/parts/people.o/{o.module.css,index.tsx,part.json}`: class `isTitleWrap`, variant `title-wrap`; the rule `#future-heading:has(.isTitleWrap)` sets `text-wrap: wrap`. Runs 39891679733, 39891679693, 39891679931 and 39891744638 were taken at tip b3a92c3, where the same `text-wrap: wrap` was a plain `.title` rule in people.card (same computed value; moved into the flag when the gate showed it reads text-wrap-style, and into people.o to stay in this task's writes). Flag-on runs are `dispatch` items.
- Probes `people-title-crash.json` and `people-title-bisect.json` (packages/measure-chromium/profiles/, run by the dispatches) are in commits 24056640b and 4e94d2451 of ci/people-title-crash-fix, not in the landed tree.

## General lesson

A fix chosen by a look proof still needs the measurement that it stops the crash: the bare inline-block that stopped the crash
had width 0, so it stopped the crash because it removed the `o` from the line, not because it was a block.
