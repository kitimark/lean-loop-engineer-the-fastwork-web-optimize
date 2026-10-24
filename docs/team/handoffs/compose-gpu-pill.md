# compose-gpu-pill handoff

Branch: worktree-wf_74c62bb3-3eb-1. Worktree: .claude/worktrees/wf_74c62bb3-3eb-1. No CI run pushed (none needed; accepted limit).
Revive round 2026-10-24: main merged (no conflicts), list re-decided, goldens regenerated from Lean.

State: lean/Fw/Parts/Gpu.lean lists 13 (part, variant) entries, each with an engine split (`Engines`: both, webkit, chromium),
a mechanism and a ledger row `n` (index into research/findings/ledger.json, 2026-10-24). Fw.Wire.Compose.varJson emits `gpu`
(mechanism) and `gpuEngines` (label). Compose.tsx shows a GPU pill and "GPU (engines): mechanism" text per variant.
cmpReal in lean/Fw/Ops/Golden.lean is regenerated from the current registry and ledger (JSON of apps/console-api
readComposeRegistry + readLedger); `#guard` there checks every Gpu entry names a registry variant.

Listed: hero.exit:threaded (both), platform:fade-threaded (WebKit), morph.panel:threaded (both), morph.panel:const-bounds (WebKit),
hero.countdown:strip, morph.countdown:strip, hero:scene-pause, morph.columns:idle-none, pain:dark-scroll,
people.o:preview-translate (all both), nav:clip-box, nav:bar-fixed, nav:logo-3d (WebKit).
Left out (docstring in Gpu.lean): engine.scroll:unthrottle, morph.tween:waapi*, hidden-pause variants, hero.accent:*,
nav:earn-no-transition, pain:dark-static. Theorems pin unthrottle and waapi as non-GPU.
WebKit scroll-driven threading: ThreadedScrollDrivenAnimationsEnabled default true (UnifiedWebPreferences.yaml:8518-8531@862f17d).

Verified: lean/scripts/check.sh green; console-api 781 and console-web 111 tests green; both typechecks clean.
Open: no compose zod schema in packages/contracts (TS types carry gpu, gpuEngines); the lead rebuilds and restarts the console.
Regenerate goldens: cd lean && lake env lean --run scripts/OpsGolden.lean (after lake build Fw.Ops.Golden).
