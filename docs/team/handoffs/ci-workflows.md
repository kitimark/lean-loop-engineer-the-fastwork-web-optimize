# Handoff: ci-workflows (W1 + W2 of docs/team/public-ci-brief.md)

State: workflows drafted under `.github/`, committed on the worktree branch. Nothing has run on GitHub (no remote yet).
`actionlint` exit 0, no findings, on all four workflows and three local actions.

Read first: `.github/README.md` (workflows, `fw ci` flow, caveats, harness changes), then the workflow you want.

Files: `workflows/{lean,chromium-counts,breakpoint-gate,webkit-sim}.yml`; `actions/{setup-lean,setup-pnpm,gate-engine}`;
`scripts/{verify-snapshot,gate-shards,merge-gate,gate-smoke}.mjs`, `runner-info.sh`, `check-simulator.sh`; `actionlint.yaml`.

Conventions: every action pinned by full SHA (git ls-remote); `permissions: contents: read`; no secrets; no
`pull_request_target`; inputs only through `env:`; `persist-credentials: false`; image passed between jobs as a zstd'd
`docker save` artifact with an image-id check (GHCR is the documented alternative); snapshot verified in step 1.

Dry-run evidence (local, arm64 container on a Mac, not a runner): image build + save/load, counts run, gate shards plan,
merge-gate with synthetic shards (8 shuffled shards byte-identical to one file; missing and duplicate shard exit 1),
gate-smoke (reproduces the hang below in 20 s per page). Not run: lean.yml end to end, webkit-sim.yml (Simulator).

Open items:
- Chromium breakpoint gate hangs on the ORIGINAL page at width >= 1000 px in an arm64 Linux container (renderer in futex
  wait after Emulation.setDeviceMetricsOverride; 430/800 px and the rewrite are fine; Playwright Chromium too). Unknown
  on a real runner. gate-smoke.mjs fails the job fast. Font and AppArmor (sysctl line added) hypotheses untested.
- Harness changes: H1 `--num-raster-threads=2` in measure-chromium run.mjs (workflow greps for it); H2 host.mjs reads
  `FW_DOCKER_CPUS` and passes `--cpus`; H3 gate Chromium launch fix if the hang is real on the runner.
- Not built: the `fw ci` command and console import (only specified in the README).
- Unchecked on the real runner: Lake cache size, artifact quota (image ~261 MB of 500 MB), xcode-27 runtime build 24A434.

TS glue stand-ins (no decisions in them): the scripts above; shard planning and merge are structural only, verdicts stay
in the gate's own code and `fwcore`.
