# Handoff: tween-platform-scope

**State.** Branch `worktree-wf_c156a96a-23d-1`, round 3 on 5db1e155: note, handoff, census JSON only. Flag code and
`ci/tween-platform-scope` are at 50dbdd6e; `ci/tween-platform-scope-base` is merge-base c62aae1c plus a marker.

**Verified.**
- `lean/Fw/Parts/MorphTweenOpt.lean`, "MT-R, the scoped arm": 8 theorems, standard axioms only, `check.sh` green.
- Chromium, touch, 3 runs per arm (MEASURED): −108 per frame (500-508), −114 per frame (509-530), −3745 per run;
  frames 498-499 give 268 of it.
- Frames 518-530: 318 elements per frame in `waapi` with no rAF is the WAAPI tween (scoped 203-204, faithful 85-86).
  `trace.Layout.dirtyObjects` is 32 in all arms: driver-independent, source open (artifacts `chromium-counts-rewrite-r*`
  of 39337826915, 39337815445, 39337848138).
- Census row "nav + hosted panel, live": 103 descendants, model 71 (+1 pseudo), in
  `results/tween-platform-scope/nav-live-census.json`.
- Gate: the not-ok cells of flag runs 39337856330 and 39340504860 lie inside the base's measured set, 39355333307 at
  c62aae1c (`pain-1440`) plus 39314718340 at 1791b7ec (`desktop-1512`, commission-margin-recur.md:53-54 on main).
- webkit-sim 39357698535 (`fw=morph.tween:waapi-scoped`, target rewrite, lead-dispatched): success, scroll style 667
  and 646, one recovered `Runtime.evaluate` timeout per pass. Control 39358530780 (no `fw`): success, 667 and 647.

**Open.**
- `fw run` cannot dispatch webkit with inputs: Layout.lean:414 `workflowInputs .webkit` lacks `target`/`fw`, and
  :440 `dispatchInputs .webkit = []`. Until a task fixes both, the lead dispatches webkit-sim runs with inputs.
- Residual: 117-118 elements per late frame above faithful. The live nav + panel holds at most 104 + p of them (p its
  pseudo-elements, 1 in the SSR model), so at least 117 − 104 − p, about 12, sit outside the nav (INFERRED). This
  and the 32 layout objects are the morph-nav-scope follow-up.
- Preset inclusion is the lead's decision. The WebKit saving stays INFERRED.

**Conventions.** `waapi` is the frozen comparison arm; after editing part.json, run `Fw.Preset.Gen.run`.

**Read first.** `research/notes/2026/10-20-tween-platform-scope.md`, `results/tween-platform-scope/*.json`.
