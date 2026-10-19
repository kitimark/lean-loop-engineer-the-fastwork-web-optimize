# CI telemetry: one artifact per CI job, to find what to optimize in CI itself

Task `ci-telemetry`. Every wired job uploads `telemetry-<job>` (7 days) with one `telemetry.json`: who and where it ran,
the machine, queue time, every step span, CPU / memory / load / disk probes every 5 s, cache sizes and the Simulator boot
time. `pnpm -s fw ci telemetry <github|circleci> <id>` downloads them, stores them and prints each step against its own
history. Slow or not is Lean; the producer and the collector only measure and carry.

## Pieces

| piece | where | decides |
|---|---|---|
| record schema, JSON round trip, span names, slow verdict | `lean/Fw/Ci/Telemetry.lean` (op `ci.telemetry`) | everything |
| goldens (9 cases, generated) | `packages/contracts/golden/ci/telemetry.jsonl`, `lean/scripts/TelemetryGolden.lean --check` in `check.sh` | |
| producer (node, no dependencies) | `scripts/ci-telemetry/` (`cli.mjs`, `lib.mjs`, `sampler.mjs`) | nothing |
| GitHub composite action | `.github/actions/telemetry` (`mode: start`, `cache`, `finish`) | nothing |
| collector | `apps/runner/src/ci-telemetry.ts`, `fw ci telemetry` | nothing |
| store | `<main checkout>/.fw-console/telemetry/records.jsonl` (gitignored; one line per job record) | |

## The record (Lean `Fw.Ci.Telemetry.Record`)

`schema` 1; `ident` {provider, lane, job, runId, commit, class}; `machine` {os, arch, cpu, cores, memMb};
`times` {createdMs, startedMs, endedMs, simBootMs}; `steps` [{name, startMs, endMs, exit, netBytes}];
`probes` [{atMs, cpuPct, memUsedMb, loadCenti, diskFreeMb}]; `cache` [{key, hit, restoredBytes, savedBytes}].
The decoder refuses any other schema and any missing field; `recordOf_recordJson` proves the round trip.

## Verdict (reuses `Fw.Obs.Timing`)

Each record gives spans `(queue)` (created to started), each step, `(sim boot)`, and `(job)`. A span is a
`Timing.Sample` with `tool` = lane, `step` = `job/name`, `kind` = `provider/class`, so the baseline is the history of
the same (lane, job/step, provider, runner class) only (`kindOf_inj`, `key_ne_of_class`: a macOS run or a CircleCI run
never moves a Linux GitHub baseline). Slow = longer than max(budget 5 s, 3/2 of the median of the last runs) with at
least 3 earlier runs (`slow_iff` branches: `slow_of_ceiling`, `slow_of_window`, `not_slow_of_neither`). The window is
oldest first by start time (`byStart_perm`), so the order of the input does not matter.
Limit: job and step names are joined with `/`; a `/` inside a job name could alias two keys.

## Producer

```
node scripts/ci-telemetry/cli.mjs start  [--lane L] [--job J] [--class C] [--every ms]
node scripts/ci-telemetry/cli.mjs step   <name> -- <cmd...>     # runs cmd, appends one scripts/span.sh line, returns its exit status
node scripts/ci-telemetry/cli.mjs cache  <key> <path>           # size of a restored cache directory
node scripts/ci-telemetry/cli.mjs sim-boot-ms <n>
node scripts/ci-telemetry/cli.mjs finish [--out file]           # stops the sampler, writes telemetry.json, prints the step table
```

State is in `FW_TELEMETRY_DIR` (default `$RUNNER_TEMP/fw-telemetry`, else the temp dir). Spans use the `scripts/span.sh`
line format, so `FW_TIMINGS_FILE=$FW_TELEMETRY_DIR/spans.jsonl` also takes the spans a script already writes (`lean.yml`
does this for `check.sh`). Every command but `step` exits 0 on any internal error: telemetry never fails a job.

- Sampler: Linux reads `/proc/stat` and `/proc/meminfo`; macOS `vm_stat` (memory) and `os.cpus()` (CPU), machine name
  from `sysctl`. Load is `os.loadavg()`, disk is `statfs` of the telemetry directory. At most 360 probes are kept.
- Runner class: `ImageOS-RUNNER_ARCH-<cores>c` on GitHub (for example `ubuntu24-arm64-4c`), `<os>-<arch>-<cores>c`
  elsewhere, `FW_RUNNER_CLASS` overrides.
- GitHub: `finish` makes one best-effort call to the jobs API (`GITHUB_TOKEN`, 15 s cap) and takes this job's step
  list (all steps, `uses:` steps included) and the true queue time (`created_at` to `started_at`). If the call fails the
  collector fills the steps from `gh run view --json jobs`; the queue time then stays empty (that reply has no job
  creation time).

## GitHub wiring

`.github/actions/telemetry` is used in these jobs (`mode: start` after `actions/checkout`, `mode: cache` after
`setup-lean` where there is one, `mode: finish` last with `if: (always()) && steps.stale.outcome == 'skipped'`):

| workflow | jobs | artifact |
|---|---|---|
| `breakpoint-gate` | `site`, `gate` | `telemetry-site`, `telemetry-gate-<engine>-<job>` |
| `chromium-counts` | `site`, `image`, `counts` | `telemetry-site`, `telemetry-image`, `telemetry-counts-<target>-<run>` |
| `lean` | `lean` | `telemetry-lean` |
| `premise-tests` | `engine` | `telemetry-engine-<engine>` |
| `webkit-sim` (macOS, xcode-27) | `site`, `sim` | `telemetry-site`, `telemetry-sim-<vm>`; `sim` also records the Simulator boot |

Each lane's row in `Fw.Ci.Trigger.table` lists `.github/actions/telemetry/**` and `scripts/ci-telemetry/**`, so a change to
the producer runs those lanes. The workflows keep `permissions: contents: read`.

## Collector

```
pnpm -s fw ci telemetry github  <run id>
pnpm -s fw ci telemetry circleci <pipeline id> [--slug gh/<owner>/<repo>] [--store dir]
```

GitHub: `gh run download <id> --pattern 'telemetry-*'` (through the request budget). CircleCI: pipeline to workflows to
jobs to each job's artifacts, and per job `queued_at` / `started_at`. The token is `$CIRCLE_TOKEN` or the macOS
Keychain item `fw-circleci-token`, read inside the request, sent as the `Circle-Token` header, never printed or put
into an error. Replies are parsed leniently (raw control characters inside strings are escaped). The store keeps one
record per (provider, run, job); the same run collected again replaces its record. Then one `ci.telemetry` call judges
every stored record against the ones before it and the table of the new run is printed, with `SLOW` lines.

## CircleCI: the config lines for the pilot (not applied here)

For each heavy job of `.circleci/config.yml` (circleci-pilot owns that file):

```yaml
    environment:
      FW_TELEMETRY_DIR: /tmp/fw-telemetry
      CIRCLE_PIPELINE_ID: << pipeline.id >>     # the collector takes the pipeline id
      FW_RUNNER_CLASS: docker-medium            # the job's resource_class
    steps:
      - checkout
      - run: node scripts/ci-telemetry/cli.mjs start --lane <lane> --job <job>
      - run:
          name: install
          command: node scripts/ci-telemetry/cli.mjs step install -- pnpm install --frozen-lockfile   # wrap each step to time
      - run:
          name: telemetry finish
          when: always
          command: node scripts/ci-telemetry/cli.mjs finish
      - store_artifacts:
          path: /tmp/fw-telemetry/telemetry.json
          destination: telemetry/telemetry.json
```

The collector looks for the artifact whose path ends in `telemetry.json`. CircleCI has no in-job step list, so every
step to measure is wrapped with `step`. Network bytes are recorded only where a tool reports them (none yet).

## Limits

- Network bytes (`netBytes`): no tool in these jobs reports them; the field stays empty.
- Cache `savedBytes` is the growth of the directory during the job, an upper bound of what the post step saves.
- Simulator boot time only in `webkit-sim` job `sim`, in whole seconds.
- Wrapper steps (`step`) can nest inside a GitHub step of the API list; names differ, so each is judged on its own.
- A job that dies before `finish` (runner lost, timeout) writes no record.
