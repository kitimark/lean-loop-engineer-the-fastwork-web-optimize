# Handoff: wait-guard-enforce (round 5, mechanical fixes in grammar B)
State: branch worktree-wf_d7eeac82-4cd-1, head = the "wait-guard r5" commit (r4 head 9571b16 and main merged in).
- Round 5 (task wait-guard-enforce-2): the tool shell may be zsh 5.9, so `EPOCHSECONDS` left `clocks` (now only
  `SECONDS`) and joined `noBoundVars` with `_ OPTIND LINES COLUMNS BASH_ARGC`; `isDec` takes 1..18 digits. 3 `r5:`
  golden rows (116 total) + #guards. Eval 6429 real records: 0 newly allowed, 1 newly denied (the r4 reviewer's own
  EPOCHSECONDS probe), organic false denies 0. Doc: "The tool shell may be zsh" in docs/team/tools/wait-guard.md.
Round 4 notes follow.
- Round 4, Lean first (lean/Fw/Ops/Wait.lean): a loop bound is only an element of the allowlist grammar B
  (`atomParse`: `[ V OP N ]`, `[[ V OP N ]]`, either order, OP -lt -le -gt -ge; `(( v OP N ))` with < <= > >=;
  V = `$v` `${v}` `"$v"`, N decimal, no special vars (`noBoundVars`), clocks only toward the exit (`varOk`)).
  Theorems: boundAtom_iff, grammar_only, subst_never_bound, seconds_direction, relOk_shape; body_irrelevant and
  readLoop_input_free kept. condStep/comb unchanged in shape; condPart now passes the words with a leading `!` (fails B).
- Also: backslash-newline joined (stepPlain), `read -n 0|-N 0|-t 0` not a read (zeroArg), `2>/dev/null` not a device
  (outRedir), git `worktree|stash list`, `remote [-v|get-url]`, `config --list|--get*` producers (gitReadOnly).
- Deviations from the lead grammar, all fail-closed: `timeout N cmd` is not a condition bound (`while timeout 5 x`
  repeats; it bounds only as a wrapper), `<`/`>` not in `[ ]`/`[[ ]]`, `(( ))` takes bare names only, `test`/`!` not in B.
- Goldens: ops.wait.jsonl 113 rows (`lake build Fw.Ops.Golden fwcore`, then `lake env lean --run scripts/OpsGolden.lean`);
  every round-3 reviewer deny probe is a `#guard` and an `r4:` golden row.
- Eval (MEASURED, real spool 4810 records): 4807 allow, 3 true-positive denies, 0 false denies; vs round 3: 0 newly
  denied, 2 newly allowed (round-3 false denies). Synthetic 80: 1 mismatch by design (`$SECONDS -ge $end`).
  Threat model + blind spots: docs/team/tools/wait-guard.md.
Enforce switch (lead hands to the user after land):
  1. main checkout: `cd lean && lake build fwcore`
  2. probe, must print allow: `echo '{"op":"ops.wait","cmd":"while read l; do echo $l; done < f"}' | lean/.lake/build/bin/fwcore`
  3. write `{"mode":"enforce"}` to `.fw-console/wait-guard.json` (or `FW_WAIT_GUARD=enforce`); back out with `{"mode":"shadow"}`.
Open: blind spots listed in the doc (quote removal makes `'$i'` a variable, unset counter, eval, `bash -c` bodies).
No checker run (no Agent tool in this session); docstrings self-checked on the 6 points, mathview lint clean.
Read first: docs/team/tools/wait-guard.md, then the Wait.lean module doc and the grammar block (isName .. boundAtom).
