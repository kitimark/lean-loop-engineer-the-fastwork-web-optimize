# Handoff: wktr-local (WKTR lane on GitHub CI)

State: branch `worktree-agent-a582f055d40dee992`; CI branch `ci/wktr-local` head d308206 (README results and this
handoff are committed after it, not pushed; they touch no CI input that needs a re-run).
CI runs (all green): 39036983052 (cold, 3 jobs, 6 passes), 39042087508 (cold + warm, 3 jobs, 12 passes).
Read first: `packages/measure-wktr/README.md` (method, cited internals, limits, results table).

What works: prebuilt WebKit CI iOS-sim archive r324039 (Xcode 26.5, iOS 26.5) runs on `macos-26`; Node driver speaks
WKTR's socket protocol (no webkitpy); harness injected into a temp copy of index.html; per scroll step it records
styleRecalcCount / lastStyleUpdateSize / renderingUpdateCount (+ layer, layout, compositing, invalidation counters).
Artifacts per job: `counts-[warm-]<p>.json` (schema fw.wktr.scroll/1), raw/stderr, runner.json; `wktr-classes` has
classes (cold `classes-*`, warm `classes-warm-*`).

Result: only renderingUpdates and layerFlushes are deterministic (harness cadence). Every style/layout/compositing
count is quarantined (kMax 4, tMax 24), cold and warm alike; per-step jitter is 2-3 recalcs. Cause not found
(INFERRED: page timers/animations; not lazy loads).

Conventions: one macOS job at a time (`max-parallel: 1`), archive restored/saved by actions/cache inside the job,
push paths filter from the lead, actions pinned by sha, no WebKit binaries in git, archive extracted to an empty dir.

Open items:
- `src/reduce.mjs` is a TS stand-in (interval sums, deltas, parsing): needs a Lean spec and golden vectors; tests in
  `test/wktr.test.mjs` pin it meanwhile.
- Recalcs per frame exceed 1 (about 6 vs 2 rendering updates), so lastStyleUpdateSize loses most sizes
  (`undercountedRecalcs`); a hooks mode that wraps the update would recover per-recalc sizes.
- Find the jitter source (freeze timers / pause CSS animations in the harness, then re-class) before using these counts as a gate.
- Viewport is the device screen (402x820, dpr 2), not 390x844.
- GPU process crash at launch was seen once; the driver retries twice (`meta.attempts`).
- Local leftovers: none (debug device deleted, sim-lock released). `.cache/wktr-*` is gitignored.
