# Handoff: ci-trigger-scope

State: lean.yml, chromium-counts.yml, breakpoint-gate.yml now have a `paths:` filter on `push` and
`cancel-in-progress` only on `ci/**` (commit on branch worktree-agent-a71f08802f3177bf4, first commit b5504de; verified on
CI via branch ci/trigger-scope, whose extra test commits are NOT on my branch). actionlint: only the old SC2129 style note.
Read first: `research/notes/2026/10-17-ci-trigger-scope.md` (numbers, table of the 4 verification pushes).

Open for the lead to relay (I did not touch these two files):

## webkit-sim.yml (ci-webkit): replace the `push:` block and the `concurrency:` block
```yaml
on:
  push:
    branches: ['ci/**', main]
    paths:
      - 'packages/measure-webkit/**'
      - 'snapshot/**'
      - 'snapshot.lock.json'
      - '.github/scripts/check-simulator.sh'
      - '.github/scripts/verify-snapshot.mjs'
      - '.github/scripts/runner-info.sh'
      - '.github/workflows/webkit-sim.yml'
  workflow_dispatch:   # keep its inputs as they are

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: ${{ startsWith(github.ref, 'refs/heads/ci/') }}
```
No lean/ and no setup-lean: no job builds fwcore (checked: the steps use only packages/measure-webkit, the scripts above).

## wktr.yml (wktr-local): replace the `push:` block; concurrency can stay (it only runs on ci/**)
```yaml
  push:
    branches: ['ci/**']
    paths:
      - 'packages/measure-wktr/**'
      - 'packages/measure-chromium/src/classify.mjs'
      - 'lean/**'
      - 'snapshot/**'
      - 'snapshot.lock.json'
      - '.github/scripts/verify-snapshot.mjs'
      - '.github/scripts/runner-info.sh'
      - '.github/actions/setup-lean/**'
      - '.github/workflows/wktr.yml'
```
(Read from origin/ci/wktr-local at 8473028: classify.mjs is run by the classes job, fwcore is built with setup-lean.)

Conventions and caveats to tell every agent:
- Every push now starts only the workflows whose inputs it changed. A change under `lean/**` starts lean,
  chromium-counts and breakpoint-gate (all build fwcore). To run another lane on a branch: `gh workflow run <name> --ref ci/<task>`.
- If a workflow gains a new input (new script, action, package), add its path to that workflow's `paths:` in the same commit.
- main is filtered by the same paths (one `push:` key has one `paths` list); use `gh workflow run` for a full run on main.
- Cancelling a macOS run can be slow: `gh run cancel <id> --force` after a minute.
- Side finding: webkit-sim run 39036078841 (ci/webkit-fix, since 13:19 UTC) was still running at 13:50 and holds 2 of 5 macOS slots.
- Not tested: a new branch whose first push touches no input (needs the filtered workflows on main first). Docs say a new
  branch is diffed from the parent of the deepest commit pushed (INFERRED to mean only its own commits).
