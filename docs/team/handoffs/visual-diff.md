# visual-diff handoff

State: branch `worktree-agent-aebbd96bb781be5c8` on top of the integration branch (`30734ae`), not merged with newer main
(its merge conflicted; the lead lands it). Tool doc: `docs/team/tools/visual-diff.md` (read first).

Done
- `lean/Fw/Gate/Pixel.lean` (import added to `lean/Fw.lean`): `verdict`, `pixel_verdict_total`, `unsettled_never_pass`,
  `tolerance_monotone`, `identical_pass`; 22 golden cases; `goldenLines` generates the golden file.
- `packages/contracts/golden/gate/pixel.jsonl`; `packages/visual-diff/test/verdict.test.mjs` checks the TS verdict against it.
- `packages/visual-diff` (pixelmatch + pngjs only here), `.github/workflows/visual-diff.yml` (plan, site, shoot matrix
  engine x shard, report). `pnpm-lock.yaml` edited for the new package (pixelmatch 8.0.0, pngjs 7.0.0).

Conventions
- Never time anything; images are artifacts only; the gate package files are imported read-only.
- Golden regeneration: a scratch `Gen.lean` printing `Fw.Gate.Pixel.goldenLines`, compiled with `lean -o` and LEAN_PATH.

TS stand-ins (not in Lean)
- Both arms absent gives cell status `nc`; probe/part/engine plumbing; the 200 ms double-screenshot settle capture.

Open items
- Mathview lint of `Fw.Gate.Pixel` was started locally (`scripts/mathview-cached.sh`) and not read back; run it on CI.
- Settled flag is a TS capture; once `Fw.Gate.Settle` lands on main, relate it to the gate's settled-sample predicate.
- WebKit (Linux Playwright port, not Mobile Safari) and overlay/mount parts were first exercised on CI.
- Per-part tolerances: none set yet (`tolerances.json`); set them from CI results, justified per part.
- CI runs on `ci/visual-diff`: 39074978220 (identical-shots settle: 174 of 240 Chromium cells unsettled) and 39077035869
  (settle within tolerance; HEAD 743fe70): 0 pass, Chromium 82 fail / 150 unsettled, WebKit 78 / 153, 8 probes x 30 parts.
  Fails (both engines): nav, nav.hitTest, nav.langMenu, morph.columns, morph.panel, commission.typing, overlays.signup,
  people.card, people.o, hero.countdown, hero.cue, hero.accent, platform.glint (+ overlays.drawer on Chromium run 2).
  Seen in the PNGs: serif fallback glyphs in the rewrite (nav "Join waitlist", chips, stats), grey placeholder boxes for images
  and logo, a stray MENU/DRAWER/SIGN UP button strip. Chromium counts repeat across the two runs (nav.hitTest 228716 ppm both).
  Still unsettled (endless animation in a crop): pain, platform*, hero, hero.orbit, people.carousel/deck, commission.
  Next: a frozen-frame mode for those (needs a flag in the rewrite or a lead decision on pausing animations); a third run is unused.
