---
id: 2026-10-17-spk-i
kind: note
title: "SPK-i: BeginFrameControl in a linux-arm64 container, fonts from snapshot only, byte-identical count vectors"
status: draft
created: 2026-10-17
topics: [spike, decision-record, chromium, determinism, counts-lane, v-i]
---

# SPK-i (DRAFT decision record)

**Question (PLAN Appendix B).** Does linux-arm64 headless-shell in a container accept BeginFrameControl with the three
flags, with fonts only from `snapshot/`, and give byte-identical count vectors?

**Status: PARTIAL.** Two of the three parts pass; the vectors are not byte-identical overall.

**Answer.**
1. BeginFrameControl with the three flags in the container: **yes**.
2. Fonts only from `snapshot/`: **yes** (no font files in the image).
3. Byte-identical count vectors: **no** over 3 runs. By count type (Lean `measure.classify`, kMax 4, tMax 24):
   **28 deterministic, 14 stable, 8 quarantined** (50 types).

## Evidence
| Claim | Evidence | Status |
|---|---|---|
| Chromium refuses BeginFrameControl on macOS, hence the container | `headless/lib/browser/protocol/target_handler.cc` l.62-65 @317846d579b2 (PLAN §4.1; `packages/measure-chromium/README.md`) | CONFIRMED |
| Flags `--enable-begin-frame-control --deterministic-mode --run-all-compositor-stages-before-draw` (+ `--disable-gpu`, `--font-render-hinting=none`, `--force-color-profile=srgb`); 503 virtual frames per run, about 85 s wall time | `packages/measure-chromium/README.md` "One virtual frame" @ddc91b2; `docs/team/handoffs/meas-chromium.md` @878032a | MEASURED |
| Image has no fonts (`fc-list` empty, no font files); webfonts come from the snapshot only; every host except 127.0.0.1 is unresolvable | `packages/measure-chromium/src/image-check.sh` @e01f9e5; README "What is pinned" | MEASURED |
| 3 runs are not byte-identical; classes 28/14/8 | `lean-measure.md` "Goldens and conformance" @ddc91b2; README "Determinism" | MEASURED |
| Noise sources removed: rAF timestamp clock plus per-run origin; timer phase shifted by pre-commit frames; a 100 ms real-time barrier removed the PaintImage/RasterTask shifts | README "Determinism" | MEASURED |
| Remaining noise: HitTest (98-119 frames by 1, hover recompute), GC-bound types, `elementCount` (38 frames) | README, `class-policy.md` | MEASURED |
| `Network.enable` hangs beginFrame at navigation commit; in-flight requests are counted server-side | `meas-chromium.md` | MEASURED |
| Apt library versions are not pinned (image id recorded in `meta.image`) | README "What is pinned" | INFERRED not to matter |

**Evidence commit:** `e01f9e5` (lane), `878032a` (handoff), `ddc91b2` (Lean classes, README); HEAD `30e3264`.

## Missing
- Byte-identical vectors for the 28 deterministic types is true by definition; a signed "two identical runs" artifact
  for those types as a vector (not just a table) is not stored (`out/` is gitignored).
- Known gaps: software raster only (headed Mac Chrome uses GPU raster; V-a compares), programmatic `scrollTo` instead
  of touch, no raster-invalidation rects or layer census, apt versions not pinned.
- `meas-chromium-2` has uncommitted changes (clock shim, run loop, Dockerfile, apt manifest, fixtures); not evidence yet.

## Proposed V-i re-scope (for the lead)
PLAN V-i today: "Chromium: all used types deterministic". Proposed: **each used count type is deterministic, or stable
under the signed policy and used only by totals with margin 2t; quarantined types are logged and never gated on**
(`class-policy.md`; theorems `margin_exact`, `quarantined_unsound`). PLAN §4.1's own fallback ("V-i is re-scoped to the
count types that stay deterministic without compositor stepping") is not the case here: stepping works. The re-scope
is about *which types*, not about stepping.

## Next step
1. Lead signs `class-policy.md` and this re-scope (decides whether M0's "or SPK-i failure recorded and V-i re-scoped"
   clause is used). Owner: lead.
2. Decide which of the 14 stable types K1-K9 need (Layout, Paint, RasterTask, ...) and, if a type must be exact, try to
   make it deterministic (more barriers, GPU-less raster pinning, apt pin). Owner: measure-engineer (meas-chromium-2).
3. Commit a pair of count vectors for the original as the M0 artifact. Owner: measure-engineer.

## What this changes in the plan
- §4.2 V-i row and §10.2 M0 row: use the re-scoped criterion above. §4.1: add "BeginFrameControl and snapshot-only fonts
  verified (SPK-i), vectors deterministic per class".
