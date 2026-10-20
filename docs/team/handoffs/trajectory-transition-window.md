# trajectory-transition-window handoff

State: branch `worktree-wf_473f9c96-555-1`, round 2, final commit in the report. No CI dispatch: the stored runs were enough.
Read first: `docs/team/tools/trajectory-probe.md`, section "Transitions in flight"; round 1 findings are in the lead's notes.

Done (round 2)
- Lean `lean/Fw/Gate/Trajectory.lean`: `rules` (one per selector of `nav.module.css` with a transition), `durOf` (none under
  `is-morphing`), `inFlight` on the sample's own classes, `annotate` (pass ordinal), `isCore`/`flightWindow` (same rep,
  phase, epoch, ±200 ms), `settledRef` (settled end value), `judgeColour`, `judgeUnit`. The pooled `crossed` path is gone.
- Theorems: (a) `judgeUnit_self`, `byM_self`, `byStep_self`; (b) `judgeUnit_settled` (rewrite at rest alone);
  (c) `judgeEls_outside`, `judgeUnit_flight_outside`, `judgeUnit_settled_outside`, `judgeUnit_colour_chan_outside`,
  `judgeUnit_colour_alpha_outside` (any number of components); one theorem per `judgeUnit` branch; goldens
  `byM_reversed_in_flight`, `byStep_settled_red_green`.
- `reduce.mjs` twin, golden-checked in `trajectory.test.mjs`; that test also parses `nav.module.css` and requires Lean `rules`.
- Re-recorded 39442517769, 39453181962, 39455284967: mac morph of 39453181962 fails (bg close@0 at 640 and 1280, both oklab:
  the transition starts where `is-morphing` was removed), so all 8 flags stay pending and `v2-proved` is empty.
- The nav.module.css read is already declared: `apps/site/**` (trajectory-probe.yml and land.yml rows), `apps/site/src/parts/**`
  (LandSpeed `checkShReads`, land.ts `packages/gate-breakpoints`). No edit there.

Open
- Kit colour space: WebKit mid-transition colours read as oklab, settled as rgb (task kit-colour-space, owner `kit.mjs`).
- Limits: ±200 ms slack (a mirrored ramp passes buckets 4 to 6), `since` sees only nav class changes, `startLag` is measured.
- The mac morph fail needs a flag-alone run to say which flag moves the `is-morphing` removal frame.
- Coverage `new` groups make 39455284967 mac morph unjudged; `Stored.sha` is unread.

Conventions: the Bash hook refuses compound commands, so use script files in the scratchpad. Run
`lake build Fw.Gate.Trajectory` before `lake env lean --run scripts/TrajectoryGolden.lean`.
Scratch scripts (not committed): re-reduce `rr.mjs`, per-unit debug `dbg.mjs`, in-flight fraction `frac.mjs`, mutation `mut.mjs`.
