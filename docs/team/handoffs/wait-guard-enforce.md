# Handoff: wait-guard-enforce (round 6, closed variable rule in grammar B)
State: branch worktree-wf_0aa6342c-fa1-1 on main 074c13b, head = the "wait-guard r6" commit (WIP 2319c01 before it).
- Round 6 (task wait-guard-enforce-3): the `noBoundVars` denylist is gone. `varOk` (lean/Fw/Ops/Wait.lean) allows a
  variable only if (a) it is `SECONDS` with N ≤ `secondsCap` = 86400, toward the exit, or (b) `isLowerName`
  (`^[a-z][a-z0-9_]*$`), in `asg` (assigned a decimal literal at the command's top level before the loop: `litNames`,
  `topAsg`, threaded through `UAcc.asg` and `Cnd.asg`), and not in `zshLowerSpecials` (14 lowercase rows of
  `special_params[]`, zsh 5.9 `Src/params.c` l.295-442 @73d3173; pin `zsh` in refs/upstream/sources.lock.yaml + PINS.md).
- Theorems new: var_allow_iff, upper_never_bound, seconds_capped, lowerName_no_upper, addSeg_asg, condStep_asg;
  restated with `asg`: boundAtom_iff, relOk_shape, seconds_direction, subst_never_bound, grammar_only.
- Goldens: ops.wait.jsonl 131 rows (15 `r6:` rows; old allow rows got an `i=0; ` prefix, no response changed).
  Regenerate: `lake build Fw.Ops.Golden fwcore`, then `lake env lean --run scripts/OpsGolden.lean` (in lean/).
- Eval (MEASURED, main spool read-only, 7689 records): 7685 allow, 4 deny (same 4 as round 5); vs round-5 fwcore:
  0 newly denied, 0 newly allowed. Synthetic 80: 1 mismatch by design (`$SECONDS -ge $end`).
- Hook deny text (apps/runner/hooks/wait-guard.mjs) now asks for `i=0; ...` and `SECONDS` N ≤ 86400; vitest rows added.
- Docs: docs/team/tools/wait-guard.md grammar paragraph (closed rule), zsh/bash 3.2 note (EPOCHSECONDS unset in
  bash < 5.0 incl. macOS /bin/bash 3.2.57; BASH_MONOSECONDS only bash ≥ 5.3), blind spots; the Round 6 eval is in
  research/notes/2026/10-18-wait-guard-shadow-review.md (main moved rounds 1-5 there).
Earlier rounds (4-5): grammar B (`atomParse`: `[ V OP N ]`, `[[ ]]`, `(( v OP N ))`), `isDec` 1..18 digits,
  read-loop producer allowlist, `timeout N` only as a wrapper; details in the doc and git history.
Conventions: Lean first, every theorem docstring has an exact $$ statement + one sentence; every reviewer probe is a
  `#guard` and a golden row; eval scripts live in the session scratchpad (`wge-r6/cmp.mjs` compares two fwcore bins).
Enforce switch (lead hands to the user after land):
  1. main checkout: `cd lean && lake build fwcore`
  2. probe, must print allow: `echo '{"op":"ops.wait","cmd":"while read l; do echo $l; done < f"}' | lean/.lake/build/bin/fwcore`
  3. write `{"mode":"enforce"}` to `.fw-console/wait-guard.json` (or `FW_WAIT_GUARD=enforce`); back out with `{"mode":"shadow"}`.
Open: blind spots in the doc (quote removal makes `'$i'` a variable, a counter reassigned in the body to a far value,
  eval, `bash -c` bodies); bash's own specials are INFERRED all-uppercase (bash source not pinned).
No checker/runner helper (no Agent tool in this session); docstrings self-checked on the 6 points.
Read first: docs/team/tools/wait-guard.md, then the Wait.lean module doc and the grammar block (isName .. boundAtom).
