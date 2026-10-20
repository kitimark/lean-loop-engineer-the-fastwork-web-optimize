# graph-check-lean handoff

State: branch worktree-wf_06230cac-6e8-3, one commit (see git log). `sh lean/scripts/check.sh` run at the final commit (result in the report).

Done
- lean/Fw/Ops/CheckMap.lean: kinds `workGraph` (docs/team/work-graph.json) and `findingsLedger` (research/findings/ledger.json),
  checks `graphCheck` (`node scripts/checkmap.mjs file graph <f>`) and `presetCheck` (`sh -c "printf ... | lake env lean --stdin"`
  = `Fw.Preset.Gen.run ["--check"]`, cwd `lean/`). Theorems: workGraph_routed, findingsLedger_routed, incidentLedger_plain,
  presetCheck_cmd, graphCheck_cmd; precommit_covers and tracked_mapped extended and still proved.
- Golden: lean/scripts/CheckMapGolden.lean got one case; packages/contracts/golden/ops/checkmap.jsonl regenerated from it
  (check.sh already runs the golden check, so lean/scripts/check.sh is unchanged).
- scripts/checkmap.mjs: path literal gone (`file graph` mode); `--staged` sets FW_CHECKMAP_STAGED=1 and the json/jsonl/ts/graph
  modes read `git show :path` (the index blob).
- apps/runner/src/plan-check.ts: duplicate ids (`<id>: id: duplicate task id`) and non-object entries (`<graph>: tasks[i]: not an object`).
- plan-check.test: temp dirs removed (afterAll); new tests for both errors and for the index-blob read.

Timings (checkmap --verbose, warm lake): graphCheck 342 ms; presetCheck 1369 ms.

Limits / open
- presetCheck reads the ledger and golden/preset from the working tree (Gen has no blob input); a partially staged ledger is judged by its tree.
- Writes outside the task's list: lean/scripts/CheckMapGolden.lean (golden source), docs/team/handoffs.
- Read first: lean/Fw/Ops/CheckMap.lean (module doc table rows 8-9), scripts/checkmap.mjs `source`.
