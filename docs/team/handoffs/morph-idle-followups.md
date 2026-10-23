Branch: worktree-wf_1a3f883b-68d-1 (CI branch ci/morph-idle-followups). Worktree: .claude/worktrees/wf_1a3f883b-68d-1
Last commit: 6d9ac50bc (Lean reducer + IdleHold + goldens + JS twin + site tests committed; CI branch not yet pushed with them).
CI runs: webkit-sim 39915136431 base (nonce mifbase01, in progress), webkit-sim 39915146774 flag (morph.columns:idle-none, nonce mifflag01, in progress);
both lag=true cost=only target=rewrite vms=3 (3 VMs x 2 passes = 6 passes per arm). Source runs: 39903977820 base, 39903974246 flag (2 passes each).
Verified (local, not a result): Lean WkCost.lean + IdleHold.lean compile, wkcost.jsonl regenerated and --check green (81 lines), measure-webkit
lag-morphcost test and 3 site golden tests pass. Run 39903977820/39903974246 outcome by the Lean rule: overlap (all 8 cells).
Open: (a) add the 6-pass sums of the two new runs as Lean constants + theorem, rerun golden, update the note; (b) full test scripts, lean check,
merge main, dry land, review ready; (c) item 4 Chromium base 28107 re-baseline waits for counts-font-fidelity's image.
Read first: research/notes/2026/10-20-morph-idle-none.md, lean/Fw/Measure/WkCost.lean (section "Morph zones: cost per frame of two arms"),
lean/Fw/Measure/IdleHold.lean, packages/measure-webkit/src/lag/morphcost.mjs.
