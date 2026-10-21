# run-cite-check (lean-prover) handoff

State: branch worktree-wf_4ab15aff-5d3-3, Lean + wire + golden + script + tests + docs committed; `sh lean/scripts/check.sh` green.

What exists
- `lean/Fw/Gate/RunCite.lean`: `verdict : Facts → flag → match | mismatch carried | unknown why`, `check` over citations,
  wire codec, golden writer. fwcore op `gate.runCite` (registered in `lean/Fw/Wire/Gate.lean`).
- Proved: verdict_missing, verdict_no_arm, verdict_match_iff, verdict_mismatch_iff, verdict_preset,
  mismatch_lists_every_flag, mem_carried, any_carried, presets_nil_iff, covers_iff, check_length, check_unfetched.
  Axioms: propext, Classical.choice, Quot.sound only.
- Golden `packages/contracts/golden/gate/run-cite.jsonl` (11 cases incl. run 39457767229), checked by check.sh
  (`lean/scripts/RunCiteGolden.lean`), replayed by `node --test scripts/run-cite.test.mjs` (7 tests, none skipped).
- `scripts/run-cite.mjs`: `gh run download -p` of trajectory, counts, gate j0 and webkit-sim artifacts, parse arms,
  cache in `.cache/run-cite/runs.json`. Usage, artifact field file:line table, limits: `docs/team/tools/run-cite.md`.

Ledger run (2026-10-21, research/findings/ledger.json): 22 citations of 14 runs, match 11, mismatch 11, unknown 0.
- morph.tween.waapi.falsified (morph.tween:waapi): 39466378530 no flag (A/A); 39472304195, 39457767229,
  39462241403 carried morph.tween:waapi-scoped.
- morph.tween.waapiScoped.falsified (morph.tween:waapi-scoped): 39466378530 no flag (A/A); 39471466367,
  39412301221, 39449092483, 39453458295 carried morph.tween:waapi.
- nav.earn.noTransition (nav:earn-no-transition): 39464294630, 39464322751 no flag (A/A).
- Premise: 39457767229's candidate arms carried `?fw=morph.tween:waapi-scoped` (raw-*.json runs[].search), not
  hero.exit:faithful. The waapi-threshold-attr handoff names it correctly; work-graph.json:11718 cites it for waapi.

Open items
- Evidence has no role syntax for A/A or sibling-flag runs, so those citations count as mismatches. Follow-up: a
  role marker (such as `A/A 394...`) that the ledger reader skips, or per-run flags in the ledger schema.
- The node test runs by hand only (no package script or CI). Writes outside the graph: lean/Fw/Wire/Gate.lean, lean/scripts/RunCiteGolden.lean, lean/scripts/check.sh.

Read first: docs/team/tools/run-cite.md, then lean/Fw/Gate/RunCite.lean `verdict`.
