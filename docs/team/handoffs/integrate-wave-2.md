# Handoff: integrate-wave-2 (round 1, final design round)

State: branch `integrate-wave-2` (commit in the report). CI branch `ci/integrate-wave-2-r1` pushed ONCE at c6912998 (round 0 branch merged with main at 8276822d); never push it again,
dispatch `gh workflow run <wf> --ref ci/integrate-wave-2-r1` (reuse `image_run=39049264131`). Round 0 (ci/integrate-wave-2, built from ef8b2cd3) is superseded; its run ids sit in the note appendix.
Read first: `research/notes/2026/10-19-integrate-wave-2.md` (Answer table, run ids with search strings, per-flag C3 table). Data: `results/integrate-wave-2/**` (`plan.json` maps runs to pages; `gate/verdicts.txt`).

Verified (CI, Lean verdicts):
- Gate v2-proved: Chromium FAIL 248 (39253059266), WebKit incomplete (39257945326, the wave-1 phone-rotation cells). Default arm 39253066988: Chromium FAIL 249 (the same 248 + 1 commission probe), WebKit incomplete.
- The 248 are `platform.stageBg` / `platform.marquee` `will-change` ("transform" original, "auto" rewrite), identical in both arms: a main regression from 8276822d (platform-scene-faithful), not a flag effect. NOT fixed here; the owner must close it before C3 reads the gate as pass.
- Counts: recalcs 1832 > 821 (swipe-v1), 1864 > 856 (swipe-touch-v1), deterministic, 3 of 3 shards. Layers +1054 / +1119.
- 7 single-flag part pairs (Chromium only): 20 pass, 4 model-bug (pain.notes x2, people.card x2; class-premise tail jitter in base shard 0 / arm shard 2), 18 unusable. All 10 flags kept at C3 (no falsified prediction); hero.countdown prediction unchecked.
- G2 base vs preset measured (descriptive). Totals pilot is descriptive, INFERRED; F6 stays compose-check after C3.
- Tests: engine-check 19 pass, ci-paths, runner land-inputs (40) pass.

Open: (1) platform will-change gate regression on main; (2) commission probe flake (default arm failed 1 of 2 in round 0, again in round 1; cause unknown); (3) hero.countdown `census.layers <o` reads equal, unrefutable under a stable class;
(4) engine.scroll / morph.tween have no part page; (5) WebKit per-part rows not measured; (6) the g1 tail class for frames 698 to 713 needs a C3 decision; (7) TS stand-ins in wave2.mjs have no Lean twin.

Conventions: `pnpm -s fw ci wait <runId>` for waits; `gh run rerun <id> --failed` when `setup-lean` cannot download Lean (infra; seen 4 times). `stageAs` refuses a page whose arm did not run every row pair; it tags attribution.
Pipeline: download `chromium-counts-rewrite-r*` per run, then `node packages/engine-check/src/wave2.mjs check|delta|frames|f6 --plan results/integrate-wave-2/plan.json --dl <dir> --out <dir>`; delete the staged `base-*`/`arm-*` dirs from `engine-check/` before committing (48 MB).
Writes outside the task's graph writes: none.
