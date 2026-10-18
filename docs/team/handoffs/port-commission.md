# Handoff: port-commission (commission + commission.typing, faithful)

Branch worktree-agent-a3117354262e26eb7 (CI ref `ci/port-commission`). Verdict: both `faithful`; named deltas below.

## Files
- Lean: `lean/Fw/Parts/Commission.lean` (bands, smooth step, follower frame, compact, title wrap, underline trigger, scene gate; proofs: ranges, fixed point, reduced one-frame, geometric contraction),
  `lean/Fw/Parts/CommissionTyping.lean` (looping timeline viewAt: 6844 ms cycle, 38 chars at 28 ms, caret 450/450, boil frames, visual scale, observer/trigger machine; proofs: chars bounds/mono, earned/pct range+mono+end, caret cycle, token/restart/freeze),
  `CommissionGolden.lean` -> `packages/contracts/golden/parts/commission{,.typing}.jsonl` (via `lake exe partsgolden`).
- TS: `apps/site/src/parts/commission/{logic,driver,index.tsx,data,media,commission.module.css,part.json}` and `commission.typing/{logic,driver,index.tsx,media,typing.module.css,part.json}`; golden + driver + media tests.
- Driver: shrink body on the scroll engine (order 50, own rAF per frame while unsettled), scene attrs (`data-scene`, `data-render`) per the original scheduler, underline IO + 900 ms clock interval. Typing: one shared clock subscription while visible, paints only diffs.

## Shared edits (separate commits; lead merges)
Fw.lean, Golden.lean (+2 file entries), App.tsx, registry/index.ts, gen-shells.mjs (PORTED set; shell box.module.css deleted), Scope.lean (2 PartUse), scope.gen.json (regenerate), anchors.json (2 parts), `gate-breakpoints/test/scope.test.mjs` (container-width knees may be stated in viewport px: 385 and 755 for the 345.6 px container knee).

## Deltas / open
- Fonts: the rewrite has no Google Sans (not in git), so text-driven boxes are `layoutDerived`; declared props still compared.
- Typing events land on the first frame at/after the instant (timers replaced by the clock); the original's setTimeout/rAF jitter is not modelled.
- Pictures, underline and zero drawings are own placeholders; why-bring dialog not rendered (overlays).
- CSS keyframes/cubic-beziers are restated values, not in Lean (only step-end ones and JS curves are).
- Local gate (Chrome, 13 probes, parts both): pass. Result of record: CI run in the report.
- Do not reuse generic scratchpad names (patch2.py clashed with another agent).
