# Handoff: tween-platform-scope

**State.** Branch `worktree-wf_c156a96a-23d-1`, round 2 on top of af5a4b6d with main merged. Flag code is unchanged
since 50dbdd6e; `ci/tween-platform-scope` is at 50dbdd6e. Base gate branch `ci/tween-platform-scope-base` is the
merge-base c62aae1c plus a marker comment.

**Verified.**
- `lean/Fw/Parts/MorphTweenOpt.lean`, "MT-R, the scoped arm": 8 theorems, standard axioms only, `check.sh` green.
- Chromium, touch, 3 runs per arm (MEASURED): −108 per frame (500-508), −114 per frame (509-530), −3745 per run;
  frames 498-499 give 268 of it.
- Frames 518-530: 318 elements per frame in `waapi` with no rAF is the WAAPI tween (scoped 203-204, faithful 85-86).
  `trace.Layout.dirtyObjects` is 32 in all three arms, so the 32 layout objects are not the tween's.
- Census row "nav + hosted panel, live": 103 descendants, model 71 (+1 pseudo), via Vite SSR of Nav + MorphPanel.
- Gate: flag run 39337856330 has the same not-ok set as base run 39355333307 (base 39353161468 had none in Chromium).
  Flag run 39340504860 adds commission `desktop-1512-320-1512`, which no base run showed.

**Open.**
- webkit-sim with `fw=morph.tween:waapi-scoped` was not re-dispatched: a push run takes no inputs. The lead runs
  `gh workflow run webkit-sim.yml --ref ci/tween-platform-scope -f target=rewrite -f fw=morph.tween:waapi-scoped`.
  Prior runs: 39337860689 (scoped, failed on inspector timeouts), 39347638740 (control, refused without
  `target=rewrite`), 39347940719 (control, passed after 2 timeouts).
- Residual: 117-118 elements per late frame above faithful. The live nav + panel holds at most 104 of them, so at
  least about 13 sit outside the nav (INFERRED). This is the morph-nav-scope follow-up.
- Preset inclusion is the lead's decision. The WebKit saving stays INFERRED.

**Conventions.** `waapi` is the frozen comparison arm; after editing part.json, run `Fw.Preset.Gen.run`.

**Read first.** `research/notes/2026/10-20-tween-platform-scope.md`,
`results/tween-platform-scope/chromium-counts.json`.
