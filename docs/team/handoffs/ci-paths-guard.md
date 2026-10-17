# ci-paths-guard handoff

State: branch worktree-agent-a3d097fbb639816b1, commit 718fd9c (the guard) plus a cleanup commit (handoff, temp lines removed).
Task: stop a merge of main into a ci/* branch from starting every macOS lane.

## What it is
- `.github/scripts/changed-inputs.mjs`: reads the workflow's own `on.push.paths` list (one place, no copy), diffs
  `git merge-base origin/main HEAD` against HEAD (`--no-renames`), matches with GitHub's glob rules (`*`, `**`, `?`,
  `+`, `[]`, leading `!`). Prints and writes `run=true|false` (`$GITHUB_OUTPUT`, reason + files in the step summary).
  Always `run=true` unless the event is a push to `refs/heads/ci/**`; any error fails open (`run=true`).
  Env: `EVENT_NAME`, `REF`, optional `PATHS_GUARD_BASE` (default `origin/main`).
- `.github/scripts/changed-inputs.test.mjs`: `node --test .github/scripts/changed-inputs.test.mjs` (8 tests, one builds a
  throwaway repo with a main merge). The wktr guard job runs it on every start.
- `guard` job (ubuntu-24.04-arm, checkout `fetch-depth: 0`, `filter: blob:none`) in wktr, gate-gaps, sim-speed. Every other
  job needs it and has `if: needs.guard.outputs.run == 'true'` (wktr: plan, wktr, fwcore, classes; gate-gaps: site,
  collect-macos, so collect-linux and judge skip; sim-speed: plan, probe).
- sim-speed had no `paths:` list (only branch `ci/sim-speed`); I added one so the guard has inputs (measure-webkit,
  sim-speed-*, check-simulator.sh, runner-info.sh, the workflow). Change it if more files matter.
- actionlint: clean apart from 4 shellcheck infos/warnings in untouched `run:` blocks.

## Why merge-base and not before..sha
GitHub's `cancel-in-progress` concurrency cancels the older run of the same ref when a new run STARTS, even if all its
jobs skip. A per-push diff would let a docs-only push cancel a real run and then skip itself. The merge-base diff is
sticky, so the newest run still decides to run.

## Verified on CI (temporary branches, `PATHS_GUARD_BASE` pointed at a sibling ci branch; the lines are removed again)
A real skip needs a diff vs main with no workflow edit, impossible while the guard is not on main. So the base was
`origin/ci/paths-guard-base` (same commit as HEAD, empty diff), a stand-in for a main that already holds the guard.
- skipped: wktr run 39049428386, gate-gaps run 39049428379 (guard run=false; fwcore/plan/wktr/classes and site/collect-*/judge skipped; 0 macOS jobs).
- real: wktr run 39049501757 on `ci/paths-guard-real` (probe file under packages/measure-wktr): guard run=true, plan ok, wktr j1 started on macos-26 (the one macOS job), cancelled.
- NOT verified on CI: the main-push path and workflow_dispatch (covered by the unit tests only: `decide` returns run=true), and sim-speed (only runs on ci/sim-speed).
- The final text differs from the tested text by the removal of the two temporary `PATHS_GUARD_BASE` lines.

## For the lead: webkit-sim.yml (owned by webkit-green, not edited here)
Add under `jobs:` before `plan:` (same as the other three; needs the checkout pin used elsewhere):
```yaml
  guard:
    runs-on: ubuntu-24.04-arm
    timeout-minutes: 5
    outputs:
      run: ${{ steps.g.outputs.run }}
    steps:
      - uses: actions/checkout@d23441a48e516b6c34aea4fa41551a30e30af803 # v6.1.0
        with:
          fetch-depth: 0
          filter: blob:none
          persist-credentials: false
      - id: g
        env:
          EVENT_NAME: ${{ github.event_name }}
          REF: ${{ github.ref }}
        run: node .github/scripts/changed-inputs.mjs --workflow .github/workflows/webkit-sim.yml
```
and: `plan:` gets `needs: [guard]` + `if: ${{ needs.guard.outputs.run == 'true' }}`; `sim:` becomes
`needs: [guard, plan]` + the same `if:`. `merge` (needs [plan, sim], no `if`) skips by itself. If the webkit-sim
`paths:` list changes, the guard follows it with no further edit.

## Open
- Other workflows (chromium-counts, breakpoint-gate) are Linux; not guarded.
- The guard and the filter both stay: the filter avoids creating a run at all when nothing matches.
