---
id: chrome-balance-repro
kind: note
title: "Stock Chrome 156 to 158 crashes on the people title (text-wrap: balance with an inline-grid) when the machine has no fonts"
status: draft
created: 2026-10-23
topics: [chromium, crash, text-wrap, measurement, profiles]
---

# Stock Chrome crashes on the balanced people title

Task `chrome-balance-repro`, a follow-up to `chromium-desktop-crash` (`10-2x-chromium-desktop-crash.md`). Run 39878812594,
branch `ci/chrome-balance-repro` at 90bf4ab, jobs `counts (original, r1)` and `counts (original, r2)`, identical rows. The run concludes failure only because classify cannot read probe rows (no frames field).

## Answer

- MEASURED: stock Chrome crashes. Chrome for Testing linux-arm64 156.0.8078.4 (the lane build), 156.0.8078.47 (Stable),
  157.0.8103.15 (Beta) and 158.0.8118.0 (Canary) all die with SIGSEGV `SEGV_MAPERR` at 0x84. Each ran in new headless mode with no
  BeginFrameControl and no emulation. The minimal page below fails at 1280x800, and so does the original snapshot page. Those runs
  were inside the container lane, which has no system fonts at all (`docker/fonts.conf` is empty on purpose). Section "Platforms"
  shows the crash needs that no-font environment.
- MEASURED (task `chrome-crash-platforms`, section "Platforms"): the crash is not tied to arm64 or to headless. It reproduces on
  linux x86_64, headless and headed under xvfb, and on linux arm64 when the browser has no system fonts. With the system fonts of the
  hosted runner images, nothing crashed on linux x86_64, linux arm64, Windows x86_64 or macOS (arm64 and x86_64).
- INFERRED: the layout code has no per-platform branches (New headless is the real Chrome: "Headless mode shares code
  with Chrome", https://developer.chrome.com/docs/chromium/headless, CONFIRMED doc). Not run: the live fastwork.com (only the
  snapshot ran) and branded Chrome (Chrome for Testing stands in).
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

## Platforms (MEASURED, task chrome-crash-platforms)

Question: does stock Chrome crash on other platforms? Workflow `chrome-crash-probe.yml`, one free hosted runner per leg, probe
`packages/measure-chromium/probes/balance-platforms.json`, run by the same `run.mjs` and `crash-probe.mjs` code as the container lane.
Each leg downloads Chrome for Testing (CfT) for its own platform and starts it as in the matrix above (no harness flags, no
BeginFrameControl, no emulation). Variants: `min` = the minimal page at 1280, `page` = the original snapshot page at 1280,
`page-860` = the original page at 860, `min-wrap` = the minimal page with `text-wrap: wrap` (control). Builds: lane 156.0.8078.4,
stable 156.0.8078.47, beta 157.0.8103.15, canary 158.0.8118.0. Six runs on separate jobs: pushes 39889986847, 39890929696, 39892378128,
39893655746 and dispatches 39894690177, 39894741675. Counts are ok / crash / harness failure over the runs that held the leg.

| leg (runner) | system fonts | min, 1280 | page, 1280 | page-860 | min-wrap | runs |
|---|---|---|---|---|---|---|
| linux x86_64 headless (ubuntu-latest) | yes | ok | ok | ok | ok | 6 |
| linux x86_64 headed, xvfb (ubuntu-latest) | yes | ok | ok | ok | ok | 6 |
| linux arm64 headless (ubuntu-24.04-arm, control) | yes | ok | ok | ok | ok | 5 |
| windows x86_64 headless, headed (windows-latest) | yes | ok | ok | ok | ok | 6 |
| macOS arm64 headless, headed (macos-latest) | yes | canary ok 5/5, stable ok 1/1 | same | stable ok 1/1 | stable ok 1/1 | 6 |
| macOS x86_64 headless (macos-15-intel) | yes | canary ok 5/5, stable ok 1/1 | same | stable ok 1/1 | stable ok 1/1 | 6 |
| linux x86_64 headless (ubuntu-latest) | no (empty fonts.conf) | crash 4/4 | crash 4/4 | ok 4/4 | ok 4/4 | 4 |
| linux x86_64 headed, xvfb | no | stable 4/4, lane 3/4, beta 3/4, canary 0/4 crash | crash 4/4 | ok 4/4 | ok 4/4 | 4 |
| linux arm64 headless (ubuntu-24.04-arm) | no | crash 4/4 | crash 4/4 | ok 4/4 | ok 4/4 | 4 |

- MEASURED: linux x86_64 crashes, headless and headed. Every crash is signal 11 `SEGV_MAPERR 000000000084`, the same signal as the
  arm64 container runs. The headless legs without system fonts crash on all four builds, 4 of 4 runs, min and page; the headed xvfb leg crashes on page 4 of 4 on every build but on min only 11 of 16 (canary never).
- MEASURED: with the system fonts of the runner images no leg crashed, on any build the leg could load (linux, Windows: all four builds,
  every row ok in every run). So the crash needs the missing fonts, not the CPU or the OS. Without system fonts the h2 gets Google Sans (web, 18 glyphs) when the web font is ready before layout, and then it does not crash (the headed min rows that passed); when it is not ready the h2 has no font data and the balanced layout crashes. INFERRED: the crash needs a layout pass with no font at all. The title height differs too: 55.2 px at
  1280 with fonts, 77 px for the wrapped control without (37.5 versus 82.8 at 860). With no usable font the text is laid out with no
  font data, and the balance path then runs on it.
- INFERRED: the fault is a null font pointer in the balanced layout of a line that holds the inline-grid atom. The offset 0x84 with
  `SEGV_MAPERR` is a small-offset read from a null object; Blink frames stay unsymbolized, so which pointer is not known. It would be a
  Chromium bug (a font-less machine should not crash), but a real desktop user has system fonts, so only font-less environments are hit:
  minimal containers, kiosk images, or a CI job like our container lane.
- MEASURED, limit: macOS loaded only the first CfT build of each job. Every later build stalled in `Page.navigate` (60 s protocol
  timeout, counted as a harness failure, not a crash; no crash signal, no renderer-crashed event). Order decided: stable ran first in
  39889986847 (4 of 4 ok on all three macOS legs, then lane and beta stalled); canary ran first in the later runs (5 of 5 ok, then
  beta, lane and stable stalled). The cause is not isolated. So macOS beta and lane builds have no row, and macOS stable one run. Killing the browser's
  process group between variants (push 3 onward) did not change it. macOS has no way to remove the system fonts, so the no-font
  condition was not run there.
- Limits: Chrome for Testing stands in for branded Chrome; the runners' fonts and screens are what the images hold (headed Windows and
  macOS windows are 1024-1028 px wide, so `page` there lays out at that width, recorded as `innerWidth`; the width is above 860 and
  does not crash); Windows headless lays out at innerWidth 1264 for the 1280 variants and 844 for page-860 (the window frame); both are on the same side of the 860 reset as intended; the live fastwork.com was not loaded.

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
  "SIGSEGV 0x84 on load at a viewport over the 860 px reset, only when the machine has no system fonts at all (empty
  fontconfig); reproduces in Chrome 156.0.8078.47, 157.0.8103.15 and 158.0.8118.0, linux x86_64 and arm64, headless and headed; with
  system fonts it does not". It needs a signed-in Google account.

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

- §4.1 Three lanes: the Chromium lane's desktop band runs on a real Chrome bug, not on a harness artifact, but one that needs a
  machine without system fonts (our container). Real desktop users with system fonts did not crash on any platform (section
  "Platforms"), so the original page and the rewrite's title are not at risk for them. Keeping `text-wrap: wrap` in
  `desktop-1280` is a measurement workaround. The site fix belongs to the rewrite's people part: drop `text-wrap: balance` on
  the title, or make the `o` inline-block, which removed the crash in both runs. That fix should become a rewrite task with
  its own visual check.
- §6.4 Choosing what a run measures: diagnostics live in `probes/`. They are dispatched by copying them to `profiles/` on a
  `ci/*` branch until the lane reads `probes/` itself (follow-up). Done in task `chrome-crash-platforms`: the lane reads `probes/`,
  and a probe is refused in counts mode (Lean `Fw.Measure.Profile.readOk`, `runnable`).
