# C3 decision (2026-10-19, lead)

Checkpoint C3 of PLAN §10 (deadline 2026-10-19 23:15 +0700), decided at 22:55.

## Answer

| C3 criterion | Result |
|---|---|
| Wave-2 whole-page gate on `v2-proved` | PASS. Run 39271987926 (full, not narrowed, branch with the platform will-change fix, landed on main as platform-willchange): Chromium verdict pass, 7056 readings, 0 fail, 7 excused; WebKit 0 fail, 291 excused, incomplete only by the 2 phone-rotation NC cells, identical to wave 1 (accepted limit). MEASURED |
| Default arm | PASS on platform after the fix: run 39266552780, both engines. MEASURED |
| Combined counts per profile | Style recalcs 1832 -> 821 (swipe-v1), 1864 -> 856 (swipe-touch-v1), 3 of 3 shards, deterministic (research/notes/2026/10-19-integrate-wave-2.md). MEASURED |
| Proof ledger | 14 of 15 closed. `variant-hidden-pause` closed by evidence 726cc17b (its three flags are on main and pass the gate). `variant-morph-panel-rest` is cut: reported as "modelled, not proved"; `morph.panel:rest` is not in `v2-proved` |
| F6 | "statement landed, run after C3" (compose-check) |

## `v2-proved` per flag

| flag | C3 | basis |
|---|---|---|
| nav.hitTest:elements-skip | keep | 5 pass; UpdateLayoutTree 2060 -> 155, MEASURED |
| pain.notes:visible | keep | prediction met by equality; 2 model-bug rows filed (class premise) |
| people.card:mq | keep | recalcs -61; 2 model-bug rows filed (class premise) |
| morph.columns:hidden-pause | keep | 2 pass (weak) |
| morph.countdown:hidden-pause | keep | in the preset; gate pass |
| morph.mount:shift | keep | 5 pass |
| engine.scene:hidden-pause | keep | full gate 39271987926 passes every platform and engine.scene row in both engines |
| engine.scroll:batched, morph.tween:waapi | keep, unmeasured per part | no part page (accepted limit) |
| hero.countdown:strip | out of `v2-proved`; reported "modelled, not proved" | its only prediction (census.layers below the original) is unchecked: 12960 = 12960 in every shard, which the stable class cannot refute. The strip arm MEASURED more pipeline work: UpdateLayoutTree / RecalcStyleCount 1161 -> 1182, commits 1064 -> 1085, UpdateLayoutTree.elementCount 11264 -> 22445 (runs 39257533380, 39259074927). Not falsified, so the drop rule does not force it; out because G1 asks for a checked theorem pair |

`c3-preset-update` (landed 639f9475) adds `hero.countdown:strip` and `morph.countdown:strip` to the curated exclusions in `lean/Fw/Preset/Gen.lean`; the generated `v2-proved` now has 9 flags. Re-run on main at 639f9475, run 39282664077: Chromium pass (7056 readings, 0 fail, 7 excused); WebKit 0 fail, 291 excused, incomplete only by the 2 phone-rotation NC cells, the same as run 39271987926. MEASURED

## Findings recorded at C3

- The wave-2 gate failure before the fix was a main regression (4d724e12 removed the original's `will-change: transform` on the platform artboard and track), not a flag effect.
- A run narrowed to the platform part ids (39271938577) showed a Chromium paused/running difference that the full run does not; C3 cites only un-narrowed runs. The narrowed-run difference is a follow-up.
- The console preview's original arm did not run its scripts (the proxy rewrote the inline boot script and the original's hash CSP blocked it); fixed in `preview-original-missing`. CI runs load the snapshot directly and are unaffected.

## Open after C3

- `c3-preset-update` (above); g1 tail frames 698-713 class decision; `people-layout-shift` (running); gate box-model coverage of unanchored people descendants and section height (the "host font" exclusion premise is stale since the fonts ship).
