# Join waitlist button on WebKit against Chromium (task nav-cta-webkit-match)

## Answer

- **The cause is the one already proved for earn-webkit-parity, and its fix already exists as the flag `nav:earn-logical`.** The user's report
  (WebKit differs, Chromium is correct) matches the default page, which does not carry the flag.
  CONFIRMED (source, ledger n=73): the rule lists `padding-inline`; WebKit keeps its two logical longhands in the transition list without an
  animation wrapper, so no side-padding transition starts (Styleable.cpp:553-566, process-css-properties.py:~5956@862f17d); Chromium maps them to
  physical and eases them. Lean: `Fw.Parts.NavEarnWebkit.faithful_webkit_never_starts_padding`, `variant_webkit_set_eq_chromium_faithful`,
  `variant_webkit_timing_eq_chromium_faithful`, `variant_chromium_set`, `variant_chromium_timing`; value at every t: `Fw.Parts.NavEarnCurve.curve_identity`,
  `chromium_unchanged`, `faithful_webkit_snaps`.
- **The unmodified snapshot differs the same way** (CONFIRMED from source: snapshot/site/_app/immutable/assets/2.gBuqKVzi.css carries the same `padding-inline .68s` transition as the port; local debug trace, not a result: Playwright WebKit 27.2 against Chrome 155, rAF log from the flip):
  Chromium `padding-left` 0, 0.2, 0.47, 0.89, 1.47 ... px over the first frames and `padding-left, padding-right` listed as running transitions;
  WebKit snapshot, our faithful port: `padding-left` 24 px in the flip frame and only `max-width, opacity` running. So our port is faithful; this is
  a WebKit-versus-Chromium difference of the original, hence a flag (never in a preset in this task), not a port bug. With `?fw=nav:earn-logical` WebKit
  runs `max-width, opacity, padding-left, padding-right` and the padding is 0.05, 0.37, 0.73 ... px.
- **Other animated parts do not differ** (INFERRED from a local debug run, not a result; the CI frames of run 40858439757 show the logical arm within 10 px of its settled floor at 1280): the unmask `mask-position` animation and the `::after` sheen
  (`mix-blend-mode: screen`, translate) match Chromium frame by frame within anti-aliasing once the padding runs; there is no hover or press animation
  (`.btn` has none, nav.module.css:144-166).
- **Recommendation (lead):** put `nav:earn-logical` in the preset. It is already accepted by the user (2026-10-25, class L) and proved; the
  report is what the default page shows without it.

## What animates (nav.module.css:167-248)

| Property | Driver | Timing |
|---|---|---|
| max-width, padding-inline, opacity | CSS transition, restarted at the `is-hero-pill` flip | max-width and padding .68 s, opacity .2 s (to hero) or .32 s after .12 s (from hero), curve (.33,0,.2,1) |
| mask-position (unmask) | CSS animation `earn-unmask` | .98 s after .52 s, both fills, (.33,0,.2,1) |
| `::after` transform (sheen) | CSS animation `earn-sheen` | same |
| filter, transform, opacity via `--earn-out` | `--morph` write (JS driver), while morphing | per frame |

## Frame capture and the bound

Fixed first (Lean `Fw.Parts.NavEarnWebkit.frameThreshold`, `framePermille`, `frameAllowed`; golden row `frameBound` in
`packages/contracts/golden/parts/nav.earn.webkit.jsonl`): a frame passes when at most 2 per mille of the 100 px band (256 px at 1280, 78 px at
390) have a channel difference above 40. `frameOk_identical`, `frameOk_mono`, `frameAllowed_wide`, `frameAllowed_narrow`, `frameOk_snap_fails`.

Harness (`packages/premise-tests/src/earn-frames.mjs`): the real `nav.module.css` (`:global()` removed), the site's Google Sans, the hero-pill flip as
the only input, every animation paused and seeked to t in {0, 60, 120, 200, 300, 400, 520, 600, 700, 800, 900, 1000, 1100, 1200, 1300, 1500, 1800} ms,
screenshot of the top 100 px, with the earn label transparent for the verdict. Exit (leave hero pill) and entry (back to hero pill), widths 1280 and
390, arms faithful and logical. `earn-frames-compare.mjs` compares Chromium with WebKit per frame. It runs as a step of the visual-diff shoot job
(shard s0), artifacts `earn-frames-chromium` and `earn-frames-playwright-webkit`; a TS stand-in only for the compare (the bound comes from the Lean golden).

## Results (MEASURED, run 40858439757, head 07a9b1285; Linux Chrome Headless Shell and Playwright WebKit)

Changed pixels, the worst frame of 17; `settled` is the t=1800 frame (no animation); allowed is the Lean bound.

| Width | Scenario | Arm | Worst frame | Settled | Allowed | Frames over bound |
|---|---|---|---|---|---|---|
| 1280 | exit | faithful | 314 | 153 | 256 | 3 |
| 1280 | exit | logical | 163 | 153 | 256 | 0 |
| 1280 | entry | faithful | 2516 | 145 | 256 | 3 |
| 1280 | entry | logical | 163 | 145 | 256 | 0 |
| 390 | exit | faithful | 231 | 121 | 78 | 17 |
| 390 | exit | logical | 148 | 121 | 78 | 17 |
| 390 | entry | faithful | 1338 | 124 | 78 | 17 |
| 390 | entry | logical | 148 | 124 | 78 | 17 |

- At 1280 the fix is inside the bound on every frame; the faithful rule is outside it (the padding snap).
- At 390 every frame of both arms is over the absolute bound, because the settled frame already is (121 and 124 px): Linux Chromium and WebKitGTK
  draw the 36 px pill edge and the "EN" label differently at rest. This is not the animation: the logical arm's worst frame is 27 px (exit) and 24 px
  (entry) above its settled floor, the faithful entry is 1214 px above. The fixed bound is therefore not met at 390 on the Linux pair; reported, not
  re-fitted. The same capture on macOS (Chrome 155 against Playwright WebKit 27.2, debug run, not a result): 390 logical worst 62 px against 78, faithful 245
  (exit) and 1330 (entry); 1280 logical 60 against 256, faithful 295 and 2478.
- **With the label (run 40858439757 artifacts, 1280):** the same frames compared with the label text kept give a worst frame of 803 px (logical exit),
  585 px (logical entry) and 803 px (faithful exit), all above the 256 bound. The verdict frames above hide the label because text rasterization differs
  between the engines at rest, so the label text alone puts every with-text frame over the bound; the table measures the animation, the with-text numbers
  show what the text difference adds.

- Chromium is unchanged: the faithful and the logical arm are pixel-identical (0 changed pixels) on all 17 frames of both scenarios and widths.
- Earlier pushes: run 40852349397 (label metrics differ by 3 px between the Linux engines) and run 40855407833 (`text-rendering: geometricPrecision` did not equalise them); the third push fixed the label slot to 5.7em.
- Summary with every frame: `results/nav-cta-webkit-match/summary.json`.

## Limits

- Playwright WebKit (Linux WebKitGTK/WPE in CI, macOS build locally) stands in for iOS Safari; the phone check comes with the user.
- The capture seeks animations (no real-time sampling): it shows values at t, not the compositor's frame pacing.
- The harness page is a static page around the real CSS, not the built site; the built site was checked in the local debug run only (padding trace above).
- The lead and the user's look review decide whether the flag enters a preset.
