# CI for the measurement loop

Drafted locally (W1 and W2 of `docs/team/public-ci-brief.md`). Nothing here has run on GitHub yet: the first push of a
`ci/*` branch is the real test. `actionlint` passes on every workflow; the Linux commands were dry-run in an arm64
container on a Mac (Docker Desktop), which is not a GitHub runner.

## Workflows

| File | What it does | Runner | Artifacts (retention) |
|---|---|---|---|
| `lean.yml` | elan with the toolchain in `lean/lean-toolchain`, `lake build`, `lean/scripts/check.sh`; Lake cache keyed by manifest + toolchain | `ubuntu-24.04-arm` | `fwcore-linux-arm64` |
| `chromium-counts.yml` | builds `fwcore` and the counts image once, passes the image as a zstd'd `docker save` artifact (id checked after load), then N determinism runs (one VM each) with `--num-raster-threads=2` | `ubuntu-24.04-arm` | `chromium-counts-<run>`, `chromium-classes` (30 d) |
| `breakpoint-gate.yml` | builds the rewrite once, runs the 124-load matrix in 8 shards per engine (+1 sweeps job per engine), merges per engine, writes the step summary | `ubuntu-24.04-arm` | `gate-<engine>-<shard>`, `gate-merged-<engine>` (14 d) |
| `webkit-sim.yml` | boots the Simulator once per job, fails fast unless the iOS runtime build is the pinned one (24A434), runs the WebKit determinism experiment and the class merge | `xcode-27` | `webkit-sim-<vm>`, `webkit-classes` (30 d) |

Triggers: push to `ci/**` and `main`, and `workflow_dispatch` (inputs are listed at the top of each file). Never
`pull_request_target`. Every workflow has `permissions: contents: read`, no secrets, a concurrency group per
workflow and ref, and `persist-credentials: false`. Free-text inputs go through `env:`, never straight into a
script. Every third-party action is pinned by full commit SHA (resolved with `git ls-remote ... refs/tags/<tag>`).

Shared pieces: `actions/setup-lean` (elan, toolchain, Lake cache), `actions/setup-pnpm` (corepack pnpm, filtered
install), `actions/gate-engine` (pinned Chrome Headless Shell with sha256 check, or Playwright WebKit);
`scripts/verify-snapshot.mjs` (first step of every job that reads the snapshot: git tree ids against
`snapshot.lock.json`, pure Node), `scripts/runner-info.sh` (CPU, kernel, image, browser versions into `runner.json`),
`scripts/gate-shards.mjs`, `scripts/merge-gate.mjs` (structural merge, no verdict logic), `scripts/gate-smoke.mjs`
(fails in under two minutes if an engine cannot answer on the original page), `scripts/check-simulator.sh`.

## The `fw ci` flow (specified here, not built)

1. Make a branch `ci/<topic>` and push it (agents may push `ci/*` only). Or `gh workflow run <file> -f key=value`.
2. Wait with `pnpm fw ci wait <runId>` or `pnpm fw ci wait --branch ci/<topic> [--workflow <name>]` (exit 0 success, 1 failure, 3 timeout:
   call it again). Never a gh loop or `gh run watch`: the shared poller makes the GitHub calls (`docs/team/tools/fw-ci.md`).
3. `gh run download <id> -D results/ci/<id>/`. Each artifact lands in its own directory.
4. Reduce the files in Lean (`fwcore`); the console reconciler imports the run as events under a CI platform key.

The workflows do no reduction themselves beyond `classify.mjs` and the gate's `summary`, which are the same code as
locally. Raw count vectors, `sha256.txt` and `runner.json` are always uploaded so step 4 can redo everything.

## Caveats the reader must keep

- **Separate platform key.** CI counts are Linux arm64 Chromium and (for the gate) Linux Playwright WebKit. They are
  never merged with local Mac or Simulator results. Linux WebKit is not Mobile Safari. Only `webkit-sim.yml` runs real
  iOS WebKit, and only on the preview image `xcode-27`.
- **Never read time off CI as phone time.** Shared runners are noisy; only deterministic counts are compared.
- **`--cpus` is not applied yet** (harness change H2): `FW_DOCKER_CPUS` is exported but `host.mjs` ignores it.
- **Chromium breakpoint gate may hang on the original page** (MEASURED once, arm64 Linux container on a Mac): after
  `Emulation.setDeviceMetricsOverride` to a width of 1000 px or more, the renderer never answers on the snapshot page
  (430 px, 800 px and the rewrite are fine; Playwright's Chromium does the same). It is unknown whether a real runner
  does it. `gate-smoke.mjs` runs before every shard and fails the job within about 100 s instead of 60 min. The
  WebKit engine is unaffected by this and merges separately, so its table still arrives.
- **Quota.** The counts image artifact is about 261 MB against a 500 MB per-repo artifact quota (plus the other
  artifacts). Option if it gets tight: push the image to GHCR (needs `packages: write`, a deliberate widening of the
  permissions) and pass the digest, or lower `retention-days`. Cache limit is 10 GB; the Lake cache is the large one.
- **Concurrency.** 20 jobs and 5 macOS jobs at once: the gate uses up to 2 x 8 + 2 jobs, so the engines queue.
- **Preview image.** If `xcode-27` changes its iOS runtime build, `webkit-sim.yml` stops on purpose.

## Harness changes wanted (not done here, the measure packages are being edited elsewhere)

- H1: `--num-raster-threads=2` in `packages/measure-chromium/src/run.mjs` (the counts workflow greps for it and fails
  without it).
- H2: `host.mjs` should read `FW_DOCKER_CPUS` and pass `docker run --cpus`.
- H3: if the Chromium gate hang also happens on a real runner, `engines.mjs` needs another launch mode or flags for
  the Linux headless shell (the smoke step will say).

## Local checks

`actionlint` (run from the repo root), `node .github/scripts/verify-snapshot.mjs`, `node .github/scripts/gate-shards.mjs`.
