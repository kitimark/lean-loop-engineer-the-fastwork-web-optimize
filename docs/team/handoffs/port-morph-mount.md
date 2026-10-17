# Handoff: port-morph-mount (morph.mount faithful)

Branch worktree-agent-af532f9c9a68e864f; commits 4f3a769 (part) + the "shared (additive)" commit after it. CI ref
`ci/port-morph-mount`. Gate: `parts=morph.mount` dispatch run 39053169745, pass on chromium and playwright-webkit (1 probe).
Verdict: faithful (no delta in what the part restates; see boundary below).

## What it is
Original 2.DyWL8TcE.js:13040-13089 (+12911 `C`): IntersectionObserver `rootMargin 200% 0px` on the platform, arm geometry
(`height >= 0.45*vh`, `bottom <= vh+8`, vh = visualViewport ?? innerHeight), push rule `active || (delta>0 && armed)`,
capture listeners wheel/touchstart/touchmove (non-passive except touchstart) attached once via the `d` guard, scroll pin
while active (`scrollTo instant`), panel mount flag on first intersect or first taken push.
- Lean: `lean/Fw/Parts/MorphMount.lean` (core only, `lean` compiles clean; theorems armed_mono_*, takes_*, action_after/idem,
  mountNext_mono, repin_idle; LaTeX docstrings). `MorphMountGolden.lean` has `lines`; jsonl at
  `packages/contracts/golden/parts/morph.mount.jsonl` (74 lines), made by a scratch driver (`lake env lean --run`
  writing `String.intercalate "\n" lines`).
- TS: `apps/site/src/parts/morph.mount/{logic.ts,logic.test.ts,index.tsx,part.json}`; 76 tests pass, typecheck clean.

## Boundary with morph.tween (INFERRED, check at merge)
`MorphMount` props: `isActive()` (C), `onPush(delta)` (starts the tween), `onMount()`, `onReady(handle)` with
`handle.refresh()` (the original's `I()`, tween calls it when the morph goes idle/active). The part renders a hidden
`<div data-fw="morph-mount">` sentinel standing in for `.start-selling-platform` (gate anchor); real page: pass
`targetSelector` of the platform section. Pin order 101 (right after nav.hitTest 100).

## Shared files touched (separate commit, additive; lead merges)
`apps/site/src/App.tsx` (+MorphMount), `apps/site/src/registry/index.ts` (+part), `lean/Fw/Gate/Scope.lean` (+PartUse
morph.mount, dismissed js.morph-arm), `packages/gate-breakpoints/src/anchors.json` (+morph.mount), `scope.gen.json`
(regenerated via scopegen.mjs). Other morph ports add the same kind of entries: expect trivial merge conflicts.
Not done: `Golden.lean` does not import MorphMountGolden (shared; one line to append `lines`); `Fw.lean` aggregate import.

## Open
- Gate anchor is count-only (like nav.hitTest); the platform is not restated.
- Not verified in a browser: wheel/touch listener behaviour is glue over proved logic; no DOM test.
