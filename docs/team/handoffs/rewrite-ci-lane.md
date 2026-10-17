# Handoff: rewrite-ci-lane

State: branch worktree-agent-aaa08fe55843b3ed5 (merged main before the preset/fw work). Files: .github/workflows/chromium-counts.yml,
packages/measure-chromium/README.md (last section). host.mjs/run.mjs needed no change (they already had --target, --search, and refuse a
rewrite that did not hydrate).

Workflow: inputs target (both|original|rewrite), preset, fw (names as the lead asked; `?preset=<n>&fw=<flags>` is the rewrite query, the site
build prerenders it through `--config`), plus profile, runs, image_run. Jobs plan -> site -> counts (target x run, one VM each) -> classify.
Artifacts chromium-counts-<target>-<run>; chromium-classes has original/ and rewrite/ dirs and a-vs-r.txt (class(k,t) per type).

CI runs (MEASURED, one image from run 39039958580): swipe-v1 39039958580, 39040442530 (3 runs per target each); swipe-touch-v1 39040473427
(3 per target); preset strip-demo + fw hero.countdown:strip, rewrite only, 39040476482 (hydrated, config verified in counts.json). All 12 jobs
per both-run completed, attempts=1 everywhere (0 wedges). Classes (det/stable/quarantined): swipe-v1 A 27/25/10, 30/22/10; R 37/6/1, 37/7/0;
touch A 31/20/11, R 40/0/4 (EventDispatch, FunctionCall, HitTest, PrePaint, each k=25 t<=2); strip-demo R 37/7/0.

Open
- Lean `workflowInputs` chromium is still [profile, runs]; it must become [profile, runs, preset, fw] (and dispatchInputs should send preset/fw)
  or `fw run` still reports BLOCKED. Not my file.
- The frozen class table (classes.frozen.json) is original-only; an R freeze needs the 3-run worst-case rule over rewrite classes.
- Branches ci/rewrite-ci-s1..s4 exist on origin only to avoid concurrency cancels.
