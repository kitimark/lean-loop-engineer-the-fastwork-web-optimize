---
id: chrome-balance-repro
kind: note
title: "Stock Chrome 156 to 158 crashes on the people title (text-wrap: balance with an inline-grid)"
status: draft
created: 2026-10-23
topics: [chromium, crash, text-wrap, measurement, profiles]
---

# Stock Chrome crashes on the balanced people title

Task `chrome-balance-repro`, a follow-up to `chromium-desktop-crash` (`10-2x-chromium-desktop-crash.md`). Run 39878812594,
branch `ci/chrome-balance-repro` at 90bf4ab, jobs `counts (original, r1)` and `counts (original, r2)`, identical rows.

## Answer

- MEASURED: stock Chrome crashes. Chrome for Testing linux-arm64 156.0.8078.4 (the lane build), 156.0.8078.47 (Stable),
  157.0.8103.15 (Beta) and 158.0.8118.0 (Canary) all die with SIGSEGV `SEGV_MAPERR` at 0x84. Each ran in new headless mode with no
  BeginFrameControl and no emulation. The minimal page below fails at 1280x800, and so does the original snapshot page. So real
  desktop Chrome users with a window wider than 860 CSS px would crash on this page.
- INFERRED: the crash is not tied to arm64 or to headless. New headless is the real Chrome: "Headless mode shares code
  with Chrome" (https://developer.chrome.com/docs/chromium/headless, CONFIRMED doc). The faulting path is layout code that has
  no per-platform branches. Not run: headed Chrome, x86_64, macOS, Windows, and the live fastwork.com (only the snapshot ran).
- CONFIRMED by source, MEASURED by run: `white-space: nowrap` on the h2 did not stop the crash because it leaves
  `text-wrap-style: balance` in place. `text-wrap: nowrap` resets that style, and with it the page did not crash.
- No Chromium bug report was found (details below). Filing one needs a signed-in Google account, so it is a user step.
- Desktop user agent: profiles with `viewport.mobile: false` now send the Linux desktop Chrome UA. The site does not branch on
  the UA, so earlier desktop counts stay valid.
- The crash-* diagnostics and `balance-repro` now live in `packages/measure-chromium/probes/` with `"kind": "probe"`.
  `kind`, `css` and `dropFlags` are part of the Lean profile wire format (`lean/Fw/Measure/Profile.lean`), which has a golden.

## Minimal repro (MEASURED, crashes)

One `h2` in the site font (Google Sans, served locally) inside a centred flex column. It has the people title's CSS values,
restated:

```html
<div class="c"><h2><span>People still need</span> <span class="w">pe<span class="o"><span class="s"></span></span>ple</span></h2></div>
```

- `.c`: `display: flex; flex-direction: column; align-items: center; text-align: center; padding: 80px 56px`.
- `h2`: `font-size: 48px; font-weight: 500; line-height: 1.15; letter-spacing: -0.02em; text-wrap: balance`.
- `.w`: `white-space: nowrap; display: inline-flex; align-items: flex-start`.
- `.o`: `display: inline-grid; grid-template-columns: minmax(0, 0.6042em); height: 1.0417em; overflow: hidden;
  position: relative; flex-shrink: 0; min-width: 0`.
- `.s`: `grid-column: 1; width: 100%; height: 100%`.

The probe file is `packages/measure-chromium/probes/balance-repro.json` (`repro.title`). `run.mjs` serves it with `FW_REPRO=title`
and starts the browser with `FW_STOCK=cft:<version>`.

## Matrix (MEASURED, run 39878812594, r1 = r2)

Stock launch: the CfT zip `chrome-for-testing-public/<version>/linux-arm64/chrome-linux-arm64.zip`, run with `--headless
--remote-debugging-port=9222 --no-sandbox --no-first-run --user-data-dir=<fresh> --window-size=1280,800
--host-resolver-rules=<local only>`. The CDP client attaches only to load the URL and watch for a crash.

| variant | browser | page | change | result |
|---|---|---|---|---|
| cft4-min | CfT 156.0.8078.4 | minimal | none | crash |
| cft4-page | CfT 156.0.8078.4 | original | none | crash |
| cft4-page-860 | CfT 156.0.8078.4 | original | window 860 wide | ok |
| cft4-min-wrap | CfT 156.0.8078.4 | minimal | h2 `text-wrap: wrap` | ok |
| cft4-min-tw-nowrap | CfT 156.0.8078.4 | minimal | h2 `text-wrap: nowrap` | ok |
| cft4-min-nowrap | CfT 156.0.8078.4 | minimal | h2 `white-space: nowrap` | crash |
| cft4-min-block | CfT 156.0.8078.4 | minimal | `.c` `display: block` | crash |
| cft4-min-w-inline | CfT 156.0.8078.4 | minimal | `.w` `display: inline` | crash |
| cft4-min-o-empty | CfT 156.0.8078.4 | minimal | `.s` `display: none` (empty grid) | crash |
| cft4-min-o-iblock | CfT 156.0.8078.4 | minimal | `.o` `display: inline-block` | ok |
| cft47-min, cft47-page | CfT 156.0.8078.47 (Stable) | both | none | crash |
| cft157-min, cft157-page | CfT 157.0.8103.15 (Beta) | both | none | crash |
| cft158-min, cft158-page | CfT 158.0.8118.0 (Canary) | both | none | crash |
| shell-min, shell-page | lane Headless Shell 156.0.8078.4, no BFC | both | none | crash |
| harness-min | counts harness (BFC) | minimal | none | crash |

Every crash is signal 11 `SEGV_MAPERR 000000000084`. The crash needs three things: `text-wrap-style: balance` on the
paragraph, a line that holds an inline-grid atomic inline, and a window wider than the 860 px site reset. The flex container,
the inline-flex word span and the grid's child are not needed. One limit: the CfT rows keep only the last 300 characters of
the browser log, so the browser version string itself is not in the artifact. The build is fixed by the zip URL (`cftChrome`,
`packages/measure-chromium/src/run.mjs`), which exits 3 if the download fails, before any browser starts.

## Why `white-space: nowrap` on the h2 still crashed (CONFIRMED)

- `white-space` is a shorthand for `white-space-collapse` and `text-wrap-mode` only
  (`third_party/blink/renderer/core/css/css_properties.json5:8191-8193@f842f52`). `text-wrap` is the shorthand for
  `text-wrap-mode` and `text-wrap-style` (`:8215-8218@f842f52`).
- Balancing starts only when `GetTextWrapStyle() == kBalance`
  (`third_party/blink/renderer/core/layout/inline/inline_layout_algorithm.cc:69-76@f842f52`). The block algorithm also picks the
  optimal-break context from `text-wrap-style` alone (`third_party/blink/renderer/core/layout/block_layout_algorithm.cc:763-775@f842f52`).
- So `white-space: nowrap` sets `text-wrap-mode: nowrap` and leaves `text-wrap-style: balance`. `Balance()`
  (`inline_layout_algorithm.cc:140-182@f842f52`, `ScoreLineBreaker::BalanceBreakPoints`, then
  `ParagraphLineBreaker::AttemptParagraphBalancing` as the fallback) still runs. `text-wrap: nowrap` resets the style to its
  initial value, and that variant did not crash. The faulting frame stays INFERRED, from the stripped-binary analysis in the
  prior note.

## Chromium bug report

- Not found. A web search found nothing. Searching issues.chromium.org needs a sign-in. `gh search commits --repo
  chromium/chromium "text-wrap balance"` turns up nothing for a release-build SEGV. The nearest commit is 97d5f9d4bc, "Fix DCHECK
  crash in ParagraphLineBreaker" (2026-01-07, Bug 40254930), but that one is line-clamp with balance and a DCHECK only.
- User step: file a report at https://issues.chromium.org (component Blink>Layout>Inline). Attach the minimal page above and say
  "SIGSEGV 0x84 on load at a viewport over the 860 px reset; reproduces in Chrome 156.0.8078.47, 157.0.8103.15 and
  158.0.8118.0, linux-arm64, new headless". It needs a signed-in Google account.

## Desktop user agent (CONFIRMED premise)

- The first-party snapshot code reads `navigator.userAgent` in one place: the Svelte runtime test for Firefox in
  `snapshot/site/_app/immutable/chunks/BSBv9QXB.js`. No first-party chunk tests for Android, iPhone, `Mobi` or
  `userAgentData`. The rewrite (`apps/site/src`) reads no user agent. The vendor analytics under `snapshot/site/__vendor` do read
  it, but `index.html` does not reference them, and `--host-resolver-rules` makes their hosts unresolvable.
- Decision (Lean `Fw.Measure.Profile.userAgent`): `viewport.mobile: false` sends `Mozilla/5.0 (X11; Linux x86_64)
  AppleWebKit/537.36 (KHTML, like Gecko) Chrome/156.0.0.0 Safari/537.36`. That is Chrome's reduced UA for Linux
  (`components/embedder_support/user_agent_utils.cc:301-327@f842f52`). Mobile profiles keep the Android string.
  `packages/measure-chromium/src/run.mjs` takes the UA from that function. It affects `desktop-1280`, `people-o-hover` and the
  probes. Because the page does not branch on the UA, the earlier `desktop-1280` counts (39868985767, 39869000429) stay
  comparable. No rerun.

## Profile wire format (Lean)

`lean/Fw/Measure/Profile.lean` decides four things:

- `kind`: `counts` or `probe`, where absent means counts, any other name is refused, and the kind sets the directory
  (`profiles/` or `probes/`).
- `dropFlags`: a drop entry must be a flag (`--` plus at least one more character) that is not prefix-comparable with a pinned
  harness flag (`--remote-debugging-port=`, `--user-data-dir=`, `--enable-begin-frame-control`,
  `--run-all-compositor-stages-before-draw`). `pinned_kept` proves that no accepted drop list removes a pinned flag.
- `problem`: a counts profile has no `dropFlags` and no `probe.variants`, and `css` is never empty. `problem_eq_none` proves
  that the loader accepts a file exactly when every rule holds.
- `userAgent`: picks the string from `viewport.mobile`, as described above.

The twin is `packages/measure-chromium/src/profile.mjs`; `test/profile.test.mjs` checks it against
`packages/contracts/golden/measure/profile.jsonl` (31 lines, check.sh stage "chromium profile golden check").
`FW_DROP_FLAGS` had no user, so it is removed, and the profile is now the only source of drops. The `crash-probe-1` variant that
dropped `--run-all-compositor-stages-before-draw` is gone, because that flag is pinned (the run exits 1 without it, prior note).

## What this changes in the plan

- §4.1 Three lanes: the Chromium lane's desktop band runs on a real Chrome bug, not on a harness artifact. Real desktop users hit
  it on the original page, and the rewrite has the same title, so it can crash there too. Keeping `text-wrap: wrap` in
  `desktop-1280` is a measurement workaround. The site fix belongs to the rewrite's people part: drop `text-wrap: balance` on
  the title, or make the `o` inline-block, which removed the crash in both runs. That fix should become a rewrite task with
  its own visual check.
- §6.4 Choosing what a run measures: diagnostics live in `probes/`. They are dispatched by copying them to `profiles/` on a
  `ci/*` branch until the lane reads `probes/` itself (follow-up).
