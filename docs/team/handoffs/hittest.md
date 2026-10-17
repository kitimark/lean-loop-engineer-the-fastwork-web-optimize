# Handoff: hittest and spk-q (measure-engineer)

State: branch `worktree-agent-aa196aea1a6ec0f5e`, commits "Task: hittest" and "Task: spk-q". Read first:
`research/notes/2026/10-17-hittest-and-spk-q.md`, then `packages/measure-chromium/README.md` (last section).

What changed (all in `packages/measure-chromium`):
- `src/trace.mjs`: categories `blink_style`, `blink` added; `SPLITS` table (containment split, no decision logic):
  HitTest inside the overlay-ad detector -> `trace.HitTest.overlayAdDetector`; `updateActiveStyleSheets` inside an
  `IsolatedSVGDocumentHost` -> `trace.N1.svgImageDocument`; N1 keys zero-filled (`N1_KEYS`).
- `src/n0-census.js` + `src/n0.mjs` (page-side N0 census; `FW_NO_N0=1` turns it off) and `src/run.mjs` wiring
  (`meta.n0`, `n0.*` per-frame counts, zero-filled). `fixtures/sheet-mutate/` is the positive control.
- `test/pure.test.mjs`: 3 tests pass (`node --test packages/measure-chromium/test/pure.test.mjs`).

Results (CI, 3 jobs per run): swipe-v1 A HitTest quarantined(116,0) -> stable(2,0) (run 39043025881). Touch HitTest stays
quarantined: it follows EventDispatch (touchmove k/k+1 race, not fixed). N0 = 0 on A; N1 = 0 after the SVG split (it read 17).
Control runs 39043990778 (N0 and categories off) vs 39043999523 (on): no harness effect beyond touch noise.

Conventions: counts zero-filled for N0/N1 keys; no site code copied; branches `ci/hittest`, `ci/hittest-swipe`,
`ci/hittest-ctl` (control, do not land) pushed for CI.

Open:
- Lean task requests (lead): N1 net rule and SPK-q gate verdict; class handling of the by-design-quarantined
  `trace.HitTest.overlayAdDetector` and of a type absent on one arm. TS stand-ins: trace.mjs SPLITS, n0.mjs window attribution
  (extraction only).
- `classes.frozen.json` not regenerated: needs 3 workflow runs of the final harness per profile, then `src/freeze.mjs`.
- Touch race (EventDispatch/HitTest/FunctionCall/PrePaint) still open. SPK-q WebKit side open.
- Disclosure: I ran four short local debug runs (not one) while building the census; none is reported as a result.
