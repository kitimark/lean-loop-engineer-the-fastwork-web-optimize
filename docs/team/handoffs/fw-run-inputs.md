# Handoff: fw-run-inputs (console-builder)

**State:** branch `worktree-wf_b4507318-dd8-1`; the commit with trailer `Task: fw-run-inputs`. `sh lean/scripts/check.sh` green,
runner 1401 tests, contracts 7, console-api 446, ci-paths 41 green.

**Done**
- Lean `Fw.Store.Layout`: `Lane` (chromiumCounts, webkitSim, breakpointGate) with `Lane.file` and `Lane.inputs`, the one table;
  `workflowOf`/`workflowInputs` derive from it. chromium-counts gained the missing `only`; webkit-sim has 9 inputs.
- Check: `lean/scripts/LaneInputs.lean` parses the three `workflow_dispatch` blocks and fails on any difference
  (check.sh stage "lane inputs check").
- webkit: `dispatchInputs .webkit` = target, preset, fw. Blocked only on `--profile` other than `swipe-v1`
  (`blocked_webkit_iff`). `blocked_eq_none_iff` (blocked iff a needed input is missing from the lane's table),
  `blocked_some_sound`, `needs_dispatched_webkit`, `dispatch_keys_declared`.
- Gate lane: `GateRequest`, `gateProblems` (preset and fw exclusive), `gateDispatchInputs` (engines, preset, fw),
  `gateBlocked` with `gateBlocked_eq_none_iff`, `gateBlocked_none`, `gate_needs_dispatched`, `gate_keys_declared`; wire op `store.gate`.
- TS: `fw run --gate`, `--ref` now resolves the ref's own sha (`refSha`: `origin/<ref>`, else the local branch; `--sha` wins), contracts
  `GateRequest`/`GateReply`, goldens `golden/store/gate.jsonl` (+ regenerated plan.jsonl), tests in `apps/runner/test/run.test.ts`
  (dispatch args per lane replayed from goldens, refusal reasons, ref sha, gate flow).
- Doc: `docs/team/tools/fw-run.md` (recipes).

**TS stand-ins:** none new for decisions; `refSha` and the gate flow are I/O glue (gh, git).

**Allow rule (user, via the lead):** add `Bash(pnpm fw run *)` to the allow list in `.claude/settings.json`. Not edited here.
Hand over as a `!` command of the lead's usual settings-edit form.

**Open items**
- The gate's `parts`, `runs`, `free`, `times` are not sent (workflow defaults). Add to `GateRequest` if a task needs them.
- webkit `runs`/vms/sessions stay workflow defaults (the Request run count is chromium only).
- Real dispatches: see the report (run ids or the exact commands for the lead).

**Read first:** `Lane`, `blocked_eq_none_iff`, the gate section in lean/Fw/Store/Layout.lean; `runGate`, `refShaOf` in apps/runner/src/run.ts.
