# Handoff: wait-guard-enforce (round 2)
State: branch worktree-wf_64b49155-762-1, code head 70a6281 (+ this note), main merged. check.sh green; wait-guard vitest 120/120.
- Round 2 fixes the adversarial review, Lean first (lean/Fw/Ops/Wait.lean):
  - read-loop condition is exactly `while [VAR=..] read [opts] [names]` + `;`/newline, next segment starts with `do`
    (isReadCond, readHead, UAcc.cond; cond_without_do_free). `|| true`, `&&`, `; [ 1 ];`, `-u fd`, redirects deny.
  - producers are an allowlist (producerOut: git read-only subcommands, gh run list/view, cat FILE, find w/o -exec,
    seq w/o inf, ls, printf, echo; grep/rg/jq/sort/head/wc only on finite input). producer_outside_list,
    filter_needs_finite_input. `done < <(cmd)` uses the same list (inRedir fold, RAcc).
  - here-doc opens only at an unquoted `<<` (Acc.qat/lastOp, leadOpen, opWord; flushWord_quoted).
  - readLoop_bounded restated over that shape; docstring says it is a classification fact, termination is a premise.
  - `seq` removed from boundWords (`seq inf | while read` passed on it).
- Hook message (apps/runner/hooks/wait-guard.mjs) names the exact read shape, allowlist and the server smoke-test idiom.
- Goldens: ops.wait.jsonl 58 rows (`lake build Fw.Ops.Golden fwcore` before scripts/OpsGolden.lean).
- Eval (MEASURED): main spool 1189 WaitGuard records -> 1188 allow, 1 deny (true-positive gh poll), 0 false denies, 0
  misses; synthetic 80 commands (51 deny, 29 allow) -> 0 mismatches. Axioms: propext, Classical.choice, Quot.sound only.
Enforce switch (lead hands to the user after land):
  1. main checkout: `cd lean && lake build fwcore`
  2. probe, must print allow: `echo '{"op":"ops.wait","cmd":"while read l; do echo $l; done < f"}' | lean/.lake/build/bin/fwcore`
  3. write `{"mode":"enforce"}` to `.fw-console/wait-guard.json`; back out with `{"mode":"shadow"}`.
Open: blind spots listed in docs/team/tools/wait-guard.md (`$( )`, `( )`, `{ }`, function bodies, `sh -c`, `cat<<EOF`,
`$((1 << 2))`, variables naming devices/FIFOs). No checker run (no subagent tool here); docstrings self-checked and
mathview lint clean for Wait.
Read first: docs/team/tools/wait-guard.md, then Wait.lean sections Parsing, Producers, Shapes and units.
