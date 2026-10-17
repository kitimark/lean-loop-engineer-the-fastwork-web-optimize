# Handoff: chromium-ci (touch-ci-verify + class-freeze)

State: branch worktree-agent-a12778ebec5067614 (merged main 0508a5d). Details: packages/measure-chromium/README.md, last section.

Done
- Workflow chromium-counts.yml: `image_run` dispatch input (reuse one image across runs), classes artifact records image ids and pinned
  image inputs. Paths filter and concurrency unchanged.
- 6 workflow runs on one image (39038861283 build; 39038967198, 39038970307 swipe-v1; 39038973297, 39038976656, 39038979125 touch).
  Touch: 0 wedges, 1 attempt in 9/9 jobs. Local fwcore classes equal the CI artifacts for all 6 runs.
- packages/measure-chromium/classes.frozen.json (swipe-v1 and swipe-touch-v1).

Open
- Rewrite on CI: no site build in the workflow, host gets no --target; needs a `target` input and a build step.
- A `src/freeze.mjs` (fwcore classify + summarize) so the freeze is reproducible; the scratch script is not committed.
- Touch trajectory has 2 variants (frame 469 differs by one step); the k/k+1 race is open (see touch-wedge.md).
- Branches ci/chromium-ci-{s2,s3,t1,t2,t3} exist on origin only to avoid concurrency cancels; nothing to do.
