# Chromium lane: the desktop renderer crash is text-wrap in Chrome 156.0.8078.4

Task `chromium-desktop-crash`, branch `ci/chromium-desktop-crash`. Claims carry CONFIRMED / MEASURED / INFERRED.

## Answer

- MEASURED: the renderer dies with SIGSEGV (`SEGV_MAPERR` at address 0x84) about 1 s after navigation on any page wider than 860 px,
  for the rewrite and for the faithful original snapshot alike. Setting `text-wrap: wrap` on every element removes the crash
  (`tw-all-off` ok, 4 of 4 jobs on 2 targets); so does a width of 860 px (`w860` ok, 4 of 4), where the site's own CSS resets
  `text-wrap` to `unset` on the card title (`.card-module_title`, `@media (width<=860px)`); other balance/pretty rules stay on at 430
  and 860 without a crash. So the trigger is `text-wrap: balance` on the people title, which applies only above 860 px.
- MEASURED: none of 16 tested harness settings is involved. 16 harness variants (4 jobs each, 2 per run) all still crash: no `--disable-gpu`, `--font-render-hinting`,
  `--force-color-profile`, `--hide-scrollbars`, `--lang`, `--num-raster-threads`, `--disable-checker-imaging`,
  `--disable-image-animation-resync`, `--disable-new-content-rendering-timeout`, `--mute-audio`; no UA, locale or timezone
  override; no N0 census; no touch emulation; `--disable-blink-features=ScoreLineBreakerAbort`; `--disable-features=SitePerProcess`.
  (`--run-all-compositor-stages-before-draw` cannot be dropped: the harness needs it, run exits 1 in 0.5 s.) Untested:
  BeginFrameControl, `--run-all-compositor-stages-before-draw` (the harness needs both), and full Chrome vs Headless Shell, so
  whether stock Chrome 156 crashes on this page is not known (INFERRED Chrome bug: a renderer SIGSEGV on valid CSS).
- MEASURED, rewrite only (the people part): hiding `[data-fw="people"]` removes the crash, and so does `text-wrap: wrap` on
  the people title `h2` alone; `text-wrap: pretty` or `stable` on that `h2` also does not crash, and `display: inline-block` or
  `display: none` or `position: absolute` on the `o` (`[data-fw="people-o"]`) does not either. `text-wrap: wrap` on the `p` of the
  part or inside any other part, `white-space: nowrap` on the `h2`, `white-space: normal` or `display: inline` on its inline-flex
  word span, and hiding its first span leave the crash. So in the rewrite the crash needs
  `text-wrap: balance` on a paragraph whose line holds the `o`, an inline-grid atomic inline (a flex item of the title's inline-flex
  word span, blockified to grid). The original has different markup; its offending element is not narrowed (only `tw-all-off` is
  known to remove it there).
- INFERRED (static disassembly of the stripped Chrome Headless Shell, whose symbols are not available): the faulting stack runs through
  the function that holds the strings `Renderer.Layout.TextWrapBalance` and `Renderer.Layout.TextWrapPretty` (`Balance()` /
  `Optimize()`, `inline_layout_algorithm.cc:140-222@f842f52`; they call `ScoreLineBreaker::BalanceBreakPoints` or
  `ParagraphLineBreaker::AttemptParagraphBalancing`, `score_line_breaker.cc:168@f842f52`), below a six-function cycle of
  LayoutNG block layout recursion, ending in a null-pointer read at offset 0x84. The page layout of the `o` runs nested inside the
  line breaker there. A Chromium bug report was not found (the tracker needs a sign-in for search); not filed.

## Reproduction matrix (MEASURED)

Each cell is a fresh Chrome on a CI job (ubuntu-24.04-arm, Chrome Headless Shell 156.0.8078.4), loaded to the end of the 60-frame
pre-roll; `ok` = no crash, `crash` = SIGSEGV 0x84. 2 jobs per cell, identical results.

| target | width | text-wrap | result | run |
|---|---|---|---|---|
| rewrite | 1280 | site | crash | 39865150834, 39866519567, 39867671059 |
| original | 1280 | site | crash | 39865162582, 39867655875 |
| rewrite | 861 | site | crash | 39865167197, 39866519567 |
| rewrite | 1920 | site | crash | 39866519567 |
| rewrite | 860 | site | ok | 39866519567, 39867671059 |
| original | 860 | site | ok | 39867655875 |
| rewrite, original | 1280 | all `wrap` | ok | 39866519567, 39867671059, 39867655875 |
| rewrite | 1280 | h2 of people `wrap`, rest site | ok | 39867671059 |
| rewrite | 1280 | h2 of people `pretty` or `stable` | ok | 39867671059 |
| rewrite | 1280 | `o` as inline-block, hidden or absolute | ok | 39867671059 |

The lane had never run a desktop-width profile (every earlier profile is 430 px wide), so this is not a regression of the lane or
of a site change. Mobile at 900 wide, dpr 3 (width above 860) crashes on the same cause (prior branch finding).

## Workaround and premise

There is no Chrome version pin in the lane other than the Dockerfile (a version change would move every committed count),
so the lane does not change the Chrome build. Profile `desktop-1280` sets `text-wrap: wrap` on every element at document start
(`profile.css`, `packages/measure-chromium/src/run.mjs`). Premise: the page keeps its layout except where balanced or pretty
line breaking changed a line break, so desktop counts from this profile describe the page without text balancing; they are
compared only with other runs of the same profile, never with the phone or a mobile profile.

MEASURED result of the workaround, `desktop-1280` at 1280x800, 3 counts jobs per run, all jobs and the classify job green:

| target | run | counts jobs | classes over 3 runs (deterministic / stable / quarantined) |
|---|---|---|---|
| rewrite | 39868985767 | r1, r2, r3 ok | 52 / 11 / 5 |
| original | 39869000429 | r1, r2, r3 ok | 52 / 13 / 2 |

Before the workaround the same two targets at 1280 failed in every job (39865150834, 39865162582).

## Method

`packages/measure-chromium/src/crash-probe.mjs` runs the harness once per variant of a probe profile (`profiles/crash-probe-1.json`,
`crash-probe-2.json`) with `FW_LOAD_ONLY=1`, a fresh Chrome and user-data dir each, and reads the exit code (76 renderer crash,
75 BeginFrame hang, 0 ok). `run.mjs` prints the signal block on `Inspector.targetCrashed`. No counts are recorded by a probe.
