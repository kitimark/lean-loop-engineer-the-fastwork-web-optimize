# Math artifact: math for named declarations, on demand

Lean docstrings hold no math. When a user should read the math of some Lean declarations, a lead asks for an
artifact: a page that states each one in LaTeX. A fresh reviewer then checks that page against the Lean. The math
view page (`docs/plan/math-view.html`) is frozen; this procedure replaces it.

## Steps

1. **The lead names the declarations** (full names, for example `Fw.Ops.LeanFirst.Signoff.matches`) and a topic.
2. **A lean-prover exports them** from `lean/`:
   `lake exe mathview --decl <name>... --out <tmp>.json` (or `--module <M>` for one module). The command exits 1
   when a name is not exported. Each entry carries `signature`, `doc`, `autoTex` (a mechanical rendering), the
   deep statement hash `stmtHash` and `axioms`.
3. **The lean-prover writes the page**: one HTML file under `docs/` per topic. KaTeX comes from cdnjs at a pinned
   version (`https://cdnjs.cloudflare.com/ajax/libs/KaTeX/0.16.11/`, as `docs/plan/loop-plan.html` uses). Per
   declaration the page shows the name, its `stmtHash`, one English sentence and the math. The math is written from
   the Lean signature and the definitions it unfolds, not copied from `autoTex`.
4. **A fresh math-reviewer** (`.claude/agents/math-reviewer.md`) gets the declaration names and the page. It writes
   its own math from the Lean first, without reading the page's math. Then it compares the two clause by clause:
   - quantifier scope: what each binder ranges over and where it ends;
   - binders: every explicit and implicit argument appears, and no free name is left;
   - number domains: N vs Z vs Q;
   - truncated subtraction and rounding down on N;
   - `<=` vs `<`;
   - the empty input (empty list, `none`, zero);
   - list count vs set membership (repeats, order);
   - implies vs iff, and which direction is proved;
   - unused hypotheses: a hypothesis the statement carries but the proof does not need.

   It replies `agree` or `disagree` per declaration, with the clause that differs.
5. **The lead fixes the page** from a `disagree` and asks a new fresh reviewer, until every row agrees.
6. **The lead appends the rows** to `research/notes/<yyyy>/<mm-dd>-math-artifact-<topic>.md`:

   | decl | stmtHash | agree | artifact |
   |---|---|---|---|
   | `Fw.Ops.LeanFirst.Signoff.matches` | 1234567890 | agree | docs/plan/x.html |

   `agree` is `agree` or `disagree`. A later row for the same declaration wins.

## How the rows are read

- `scripts/math-pending.mjs` reads every `-math-review-` and `-math-artifact-` note. An entry is signed when its
  latest row says `agree` at the entry's current `stmtHash`. A changed statement makes the row stale.
- The lean-first gate keys a signoff on `(decl, stmtHash, role)`: `Fw.Ops.LeanFirst.Signoff.matches`. A docstring
  edit does not unsign a declaration; a statement change does.
