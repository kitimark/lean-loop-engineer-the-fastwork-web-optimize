# verdict-to-lean handoff

State: done on branch `worktree-wf_8124a487-c01-2` (see `git log -1`). `lean/scripts/check.sh` green; 15/15
`node --test` in packages/gate-breakpoints; default-run summary byte-identical to the JS rule (run-a, and two saved
runs with failures: summary.json and summary.md compared with `cmp`).

What moved: the gate's verdict rule (cell, part, truth rows, env achieved, tally, stale counts, styleValueEq) is
`lean/Fw/Gate/{Rule,Compare,Items,State}.lean`; the fwcore ops `gate.state|stale|tally|styleEq|cell` are
`lean/Fw/Wire/Gate.lean` (one entry in `Fw/Wire.lean`). `src/verdict.mjs` is now an fwcore client (one spawn per
`evaluate`); `src/summary.mjs` only groups and formats Lean's replies.

Theorems to read first: `partVerdict_pass_iff`/`_fail_iff` (a part passes iff it compared something and every
compared item is equal), `partItems_skip_invariant` + `partVerdict_setStyle` (skipped properties never change a
verdict), `partVerdict_perm`, `rollup_perm`, `tally_perm`, `blockCell_perm` (row order is irrelevant).

Conventions: numbers are exact decimals (`Rat`); truth maps travel as `[key, bool|null]` entries; anchors are
refused when a skip has no reason (`wellFormed`); display values (a/b in the report) stay in JS (`shown()`), they
decide nothing.

Goldens: `packages/contracts/golden/gate/cases.json` is built from saved runs (local, gitignored):
`cd packages/gate-breakpoints && node scripts/golden-cases.mjs out/run-a out/old-h3 out/old-h4`, then
`cd lean && lake env lean --run scripts/GateGolden.lean` writes `gate.jsonl` + `literal.jsonl` and checks every
reply against the saved summary; `lake test` runs it with `--check` semantics.

Open items:
- Two style values exactly 1/1000 apart: JS floats said differ, Lean says equal (inclusive, exact). No saved run
  hits it; a boundary-perturbed run showed the only diffs. Decide whether the tolerance should be strict.
- The CI merge job of `.github/workflows/breakpoint-gate.yml` now builds fwcore (setup-lean + `lake build fwcore`).
- `summary.mjs` and the workflow were edited outside the named write list (needed to drop the JS rule).
- TS stand-ins: none. The failures/infoDiffs grouping and labels in summary.mjs are formatting glue.
