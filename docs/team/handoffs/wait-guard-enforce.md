# Handoff: wait-guard-enforce (round 3)
State: branch worktree-wf_4586f057-5c7-1, head = the "wait-guard-enforce r3" commit (round-2 head and main merged in).
check.sh green; runner vitest 739/739 (wait-guard 172).
- Round 3, Lean first (lean/Fw/Ops/Wait.lean):
  - bound comes from the loop condition only: boundAtom (counter or `$SECONDS` ordered against a limit, `(( i < n ))`),
    condStep + comb (bash and-or exit rule, while vs until), Cnd in UAcc. Bound words in the body (date, deadline,
    `$((n+1))`, break) no longer count. Theorems: body_irrelevant, readLoop_input_free, unbounded_cond_free,
    readLoop_bounded, addSeg_* step lemmas.
  - producers: sed (no label loops), awk (no while/for/do/getline), tr, cut, uniq as filters; xargs CMD (CMD on the list);
    gh pr|issue list|view; git reflog; node scripts/*.mjs; timeout N. pnpm/npm/npx stay denied (doc + deny message).
  - `read -d $'\0'` (ansiArg); isDev (`//dev/zero`, `./../../dev/zero`); here-string `$( )` only with a finite producer.
- Goldens: ops.wait.jsonl 84 rows (`lake build Fw.Ops.Golden fwcore`, then `lake env lean --run scripts/OpsGolden.lean`).
- Eval (MEASURED, real spool 2746 records): 2743 allow, 3 true-positive denies, 0 false denies, 0 misses. Synthetic 278
  rows (ideal bash labels): 24 mismatches, all by design (17 conservative denies, mostly stdin readers) or documented
  blind spots (7). Details: docs/team/tools/wait-guard.md "Shadow review".
Enforce switch (lead hands to the user after land):
  1. main checkout: `cd lean && lake build fwcore`
  2. probe, must print allow: `echo '{"op":"ops.wait","cmd":"while read l; do echo $l; done < f"}' | lean/.lake/build/bin/fwcore`
  3. write `{"mode":"enforce"}` to `.fw-console/wait-guard.json` (or `FW_WAIT_GUARD=enforce`); back out with `{"mode":"shadow"}`.
Open: blind spots in docs/team/tools/wait-guard.md (`$( )`, `( )`, `{ }`, functions, `sh -c`, `/proc`, FIFOs, a counter
that never moves). No checker run (no Agent tool in this session); docstrings self-checked, mathview lint clean.
Read first: docs/team/tools/wait-guard.md, then Wait.lean module doc and "Shapes and units" (boundAtom, producerOut, addSeg).
