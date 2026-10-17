# Handoff: webkit-quiet + webkit-table-regen (branch ci/webkit-quiet)

Read first: `research/notes/2026/10-18-webkit-quiet.md` (answer, tables, caveats). Table: `packages/measure-webkit/classes/webkit-sim-v1.json`.

Answer: the WebKit Simulator count jitter on the free xcode-27 runner is mostly NOT host CPU load. The runner sits at 0 % idle from the
Simulator's own services; 0/1/3/6/12 burners change neither step time nor jitter (runs 39053364004, 39055950094). Only TimerFire follows
pass wall time (r 0.93). Layout/Paint/Style/InvalidateLayout jitter is not load-explained (census at rest already quarantined).
Class table over 3 independent sessions: 49 D / 9 S / 46 Q of 104; zone level gateable only for RenderingFrame, Composite, EventDispatch.

Built (glue, all in packages/measure-webkit):
- `src/hostmon.mjs` (top sampler, timer lag, burners), `src/quiet.mjs` (dose-response), `src/quietreport.mjs`, `src/quietsteps.mjs`
  (TS stand-in of the Lean rule; temporary only in the sense that Lean is the spec, goldens check it).
- `scrollrun.mjs` records `wall` and `lag`; cli: `quiet`, `quiet-report`, `merge --out`.
- Workflow `webkit-sim.yml`: inputs `experiment` (determinism|quiet), `arms`, `reps`; concurrency group per experiment (two
  determinism dispatches on one ref cancel each other; a quiet run does not).
Lean: `lean/Fw/Measure/Quiet.lean` (proved, no sorry), wire op `measure.quietSteps`, goldens in `packages/contracts/golden/measure/`.

Conventions: counts classed per type over separate CI sessions; worst of sessions wins; dispatch descriptions must be YAML-safe (no colon).
Open items:
1. The 4th/5th session (dispatch 39059517229, determinism sessions=2) was queued when I stopped; if done, merge its two session JSONs
   with the three in the note (`merge ... --out`) and refresh the JSON; the tally may worsen again.
2. Load stamps: `loadavg` decays within a pass and is useless here; use step durations as the per-step load proxy.
3. A way to lower load (stop diagnosticd/apsd inside the Simulator) is untried; it is the only dose in the downward direction.
4. `zone-baselines-webkit` should use the noise band (`maxSpread`) per quarantined type and the timer-hold mode for TimerFire.
5. fwcore tests need a Lean build (`cd lean && lake build`); `lean/scripts/check-fast.sh` is ok (96 s); measure-webkit tests 53/53.
