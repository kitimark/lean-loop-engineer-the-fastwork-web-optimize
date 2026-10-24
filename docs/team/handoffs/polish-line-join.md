branch: worktree-wf_26467d53-112-1
worktree: <main checkout>/.claude/worktrees/wf_26467d53-112-1
CI runs: none (accepted limit: no CI run)

State
- Lean: `lean/Fw/Plan/Polish.lean` section "Line preservation": `Syn` (sh/yaml `#`, ts/js `//` `/* */`, lean `--` `/- -/` nested), `scan`, `codeLines`, `lineVerdict` (ok/joined/split/changed), `pathVerdict` (unknown type = unchecked). Theorems: `lineVerdict_refl`, `lineVerdict_ok_iff`, `joined_fewer`, `split_more`, `changed_same_count`, `refused_iff`, `unchecked_never_refused`; #guard rows for the cases.
- Wire: `plan.polishLines` {path, old, new} -> {verdict, refused} in `lean/Fw/Wire/Plan.lean` (outside the task's writes, needed to reach the rule from TS).
- TS: `apps/runner/src/polish.ts` commit step asks fwcore per kept non-prose file; a refused cut is `git checkout HEAD -- path` and prints `restored <path> (the cut joined code lines)` + `VERDICT polish-cuts <task> refused-join <path>`. No TS copy of the rule (no stand-in).
- Golden: 16 `lines:` rows in `packages/contracts/golden/plan/polish.jsonl` (regenerated with FW_WRITE_POLISH_GOLDEN=1), replayed by `apps/runner/test/polish.test.ts` plus a real-fixture test of the refusal.
- Lint: `scripts/lint-check-sh.mjs` (+ test) run as a `serial` stage in `lean/scripts/check.sh`; `lean/Fw/Ci/Trigger.lean` row + `packages/contracts/golden/ci/triggers.jsonl` declare the read.

Verified
- Real history: 35f3727 and 4d0c107 give `joined`. 162a694 gives `ok`: its parent line was already joined and it only cut the trailing comment, so the Lean rule cannot see it; the lint does (ledger attribution is imprecise).
- lint-check-sh flags the 4d0c107 check.sh (lines 153, 155) and passes the current one.

Open
- Other file types (md handled by prose rules, json, svg ...) stay unchecked; past polish commits on other files not audited.
- Heredocs and regex literals are not parsed by `scan`; a `#`/`//` inside one can mis-strip (both sides alike, so a false refusal at worst).
- Read first: the Lean section and `polishCli` commit loop.
