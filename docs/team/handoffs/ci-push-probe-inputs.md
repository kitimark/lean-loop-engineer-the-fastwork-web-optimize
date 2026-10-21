# ci-push-probe-inputs (with fw-run-dispatch-pick): handoff

State: branch worktree-wf_06230cac-6e8-1; Lean check.sh green, runner tests (run, run-pick, land-inputs), ci-paths test, trajectory-line test green.

What changed
- `lean/Fw/Ci/Trigger.lean` section "The probe line": `parseLine`, `pushProbe lane msg` (run / needsLane / notAsked / refused why), one theorem per branch, `build_ok` (fw/preset exclusive, engines and widths allowlists). Golden: `probe` lines of `packages/contracts/golden/ci/triggers.jsonl` (`cd lean && lake test -- --write-ci-trigger-golden`).
- Node twin `.github/scripts/trajectory-line.mjs` + `.test.mjs` (replays the golden); `trajectory-probe.yml` job `site` reads the inputs (push: commit line; dispatch: inputs), names a step `trajectory inputs: ...`, uploads artifact `trajectory-inputs`, run-name echoes the dispatch nonce.
- `.claude/workflows/build-review.js` PREAMBLE line 16 points builders at the push route; `docs/team/tools/trajectory-probe.md` has the section.
- Message form: `[ci:trajectory-probe]` plus `[trajectory fw=a:b,c:d widths=390,1280 engines=both]` (or `preset=`). Only a line starting with `[trajectory` counts.

Found, not fixed: a run with ONE leg (one engine, one width, e.g. engines=chromium widths=390) fails job `merge` with "merge: no leg"
(download-artifact with a pattern that matches one artifact puts its files in legs/ itself, so the `find -type d` sees no leg directory).
Runs 39519445950 (push) and 39519469405 (dispatch) show it; use two widths or both engines until it is fixed (follow-up).

Verified: golden equality (Lean to node twin), ci-paths --check. CI runs: see the report (ids).

Writes outside the task lists: `lean/FwTestMain.lean` (golden wiring), `lean/Fw/Store/Layout.lean` (Lane.trajectory.inputs gains `nonce`, required by the lane-inputs check), `.github/scripts/trajectory-line.mjs` and its test.

Open items
- `needsLane` (a `[trajectory]` line without the lane token) is decided in Lean but nothing reports it; `fw ci push` should call it.
- `fw ci push` could add the `[ci:trajectory-probe]` token itself when a line is present.

Read first: the Trigger.lean section header comment, then trajectory-probe.yml step `in`.
