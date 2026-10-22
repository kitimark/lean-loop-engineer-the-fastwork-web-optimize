# compose-gpu-pill handoff

Branch: worktree-wf_74c62bb3-3eb-1. Worktree: .claude/worktrees/wf_74c62bb3-3eb-1. No CI run pushed (no CI path needed).

State: Lean list lean/Fw/Parts/Gpu.lean (6 entries, ledger n cited); `gpu` field in Fw.Wire.Compose.varJson; golden
console.compose.jsonl and layers.jsonl regenerated; cmpReal in Fw.Ops.Golden refreshed to the current registry and ledger
(it was a stale snapshot) and a #guard there checks every Gpu entry names a registry variant; Compose.tsx shows the pill
and the mechanism as text; tests in apps/console-api/test/compose.test.ts and apps/console-web/test/compose.test.tsx.

Kept: hero.exit:threaded (n6), platform:fade-threaded (44), morph.panel:const-bounds (45), hero.countdown:strip (7),
morph.countdown:strip (13), plus hero:scene-pause (40, releases about 85 composited layers).
Rejected: morph.tween:waapi (n9, registered custom property stays on main), morph.columns:hidden-pause and
engine.scene:hidden-pause (n14, n25, saves only a compositor tick), morph.countdown own clock layer (n13, not-proved, no variant).

Open: packages/contracts has no compose zod schema (TS reply type in compose.ts and CVar carry `gpu`); the lead rebuilds the console.
