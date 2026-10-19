# platform-scene-faithful handoff

State: branch worktree-wf_ebd5ee90-ef5-2, round 1 (fix round with hidden-pause-platform-clock folded in), main merged.

Delivered
- (A) `lean/Fw/Parts/PlatformScene.lean`: model of `lE`/`dE` and CSS local time; round 1 fixed docstrings only (citations lE 2715-2718, cE 2709-2713, uE 2719-2748, dE 2749-2782, platform registration 12448 + 12668-12672; premise CONFIRMED with Blink/WebKit file:line@sha and its condition: no script play()/pause()).
- `PlatformGolden.sceneLines`: R inside the $$ block (mathview lint). Golden `platform.scene.jsonl` unchanged.
- `platform/scene.test.ts`: `const` takes rootMargin from `people/shared.ts` and playState from `platform.module.css` (regex captures); source-level wiring test of `bindScene(sec, watchActive)` + cleanup. people/shared.ts not edited.
- (B) `lean/Fw/Parts/HiddenPausePlatform.lean`: variant state (`seek`, `tick`, `run`), `Inv`, `run_inv`, `hsync_platform` (shown local time = `PlatformScene.local'` of the original), `platform_visSame` (via `HiddenPause.hiddenPause_visSame`), `meets_near`/`ok_of_rect`. HiddenPause.lean not edited.
- `engine.scene`: clock runs only while `watchActive` reports active (`createResumeSync`); on unhide each animation present at the hide gets `currentTime += clock advance`. Golden `engine.scene.jsonl` (from `PlatformGolden.syncLines`) + TS conformance and wiring tests.
- Regenerated: footprint.gen.json, FootprintData.lean, FootprintRows.lean, footprint-diff.gen.json (sequence in contract-rows-from-code.md).

Verified: `sh lean/scripts/check.sh` exit 0; site typecheck + test (88 files); contracts test; ci-paths; runner land-inputs.

Limits / open
- Frame-callback gate (`iE` 2670-2673) not ported; stated in PlatformScene module doc (INFERRED same visual, work not claimed).
- Animations created while the section is hidden are not advanced on unhide (Lean covers animations alive from a shown frame on).
- `deferRendering` (content-visibility) not ported. Pixel equality: gate/visual run.
- Lead: preset row engine.scene:hidden-pause kept (B proved); finding that the flag was first proved against a port without the 100% pause is for the incident ledger; v2-report L42 untouched.
