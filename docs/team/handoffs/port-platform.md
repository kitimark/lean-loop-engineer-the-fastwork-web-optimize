# Handoff: port-platform (P5, faithful-with-delta)

Branch worktree-agent-a55b2a4dac4e7ba91, CI ref `ci/port-platform`. Gate run id is in the report to the lead.
Verdicts: platform, platform.stageBg, platform.sweep, platform.glint, platform.entries, platform.marquee = `faithful-with-delta`.

## Delta (named)
- Shield logo glyph is a neutral circle (brand asset not restated). Images are the original's public paths (`/selling/...`), absent in the repo and in `dist`.
- Locale: English only. No web font in the rewrite yet, so title wrapping differs (line counts at 390/720/861/1001); text-dependent boxes are skipped in anchors.json.
- Dead CSS not ported (paid, quote, service-card, fx swaps, tools). Checks list is in the DOM but `display:none` at every width, as in the original.

## Evidence (this Mac, short debug runs, not results)
- Section/card/stage heights equal the original at 320, 640-1600 widths (scratch compare, 13 widths); only text wraps differ. Screenshots of 4 rows at 1440 match the original by eye.
- Local: site tests 1759 pass, typecheck, build gates pass, `mathview-cached` lint 0 failing, gate package tests 41 pass.

## Files
- Lean: `lean/Fw/Parts/Platform{Section,Sweep,Glint,Marquee,Entries,Golden}.lean` (shrink, stage, sweep colour+phase, glint SMIL + play-state invariant, marquee, bezier entries table, count-up, search typing schedule with periodicity). Golden: `packages/contracts/golden/parts/platform*.jsonl` (via `lake exe partsgolden`, `PlatformGolden.files` appended in Golden.lean).
- TS: `apps/site/src/parts/platform/{index.tsx,Visuals.tsx,driver.ts,logic.ts,content.ts,media.ts,*.module.css}`, sub-parts `platform.{sweep,glint,entries,marquee,stageBg}/` (logic/driver/part.json/media.ts; tests against golden). CSS tests check the sweep/marquee/entries constants against the CSS text.
- Shared (own commit): App.tsx, registry/index.ts, Scope.lean (6 PartUse), anchors.json (6 parts), scope.gen.json, Golden.lean, Fw.lean, `scripts/gen-shells.mjs` (PORTED skips platform's box file; `box.module.css` deleted).

## Conventions / open
- Drivers: shrink = scroll-engine callback (order 95, before nav.hitTest) writing `--platform-shrink` + class; glint timer = clock subscription, entries/typing/count-up = clock ticks writing DOM text; React state only on list/play changes. Sub-part variant other than `faithful` switches the effect off (hook for optimized variants).
- morph contract kept: `data-fw="platform"` section, `--morph-fade` read by CSS, platform rect used by morph.tween/mount.
- Open: `shell-measure.mjs check` has a syntax error at line 112 in the base (not mine). Scope Lean docstring list not updated. Fonts are the next lever for PL1 text parity.
