# Handoff: latex-plan-text

State: branch `worktree-wf_1de700b0-a77-2`, commits on top of main 49277224 (see `git log main..HEAD`).

## Done
- `docs/plan/PLAN.md` rev 11.3 "math in artifacts": frontmatter revision and date, intro rev line, §0, §1.2 V-s,
  §3.1 diagram (math pages node), §5.1 M0 (axiom check), §5.3 rewritten (four steps per math-artifact.md, rows at
  the current `stmtHash`, old counts as history, example = Lean plus the page's math), §5.4 TL0, §7.1 (`math.lock.json`
  dropped), §8.2 roster, §8.5 (`math:sign` dropped), §10.2 C4 note, §10.7 (`mathview-differential` retired, pre-push
  `check-fast.sh`), R6, R24, §12.0 new row "Math in artifacts", Q25/Q28, A41, review log entry.
- `docs/plan/math-view.html` removed (A41: generator retired, page could never refresh; new rule (rev 11.3): a
  page whose generator is retired is removed; git history keeps it, last at 5e67b61f).
- `docs/plan/loop-plan.html`: Math section rewritten (no generated block, no links to math-view.html), Lean example
  with plain docstrings and the math as a caption, decision row, Q25, M0 rows, roster, commands, footer rev 11.3.
- `docs/plan/math-to-lean.html`: back-link text, one sentence on where the math column comes from.

- Round 2 (review of 93320da8): C4 "Must be true" (PLAN §10.2 and loop-plan.html) = every math row the report
  shows is `agree` at the current `stmtHash`; A41 wording "New rule (rev 11.3)"; §5.3 cites `Verdict.lean:48, 57-61`;
  loop-plan.html Lean example captioned as an illustrative kickoff sketch (not reviewed math); math-to-lean.html
  names its math source (kickoff sketch, two passes, lessons.json). Logged in PLAN App D rev 11.3.

## Verified
- Round 2 re-run, same three checks. Every relative href in loop-plan.html and math-to-lean.html resolves.
- `node docs/plan/tools/check-lean-lessons.mjs --check` green; `node --test scripts/ci-paths.test.mjs` 41 pass;
  `ci-paths --check` green.

## Open (other owners)
- Follow-up: replace the loop-plan.html illustrative example with reviewed math rows (`Fw.Verdict.better_sound`,
  `Fw.Null.land_null_prob`) per math-artifact.md.
- `docs/team/tools/math-artifact.md` (latex-teardown): still says math-view.html is frozen, and says loop-plan.html
  loads KaTeX from cdnjs (it does not; math-to-lean.html does).
- `lean/Fw/Ops/CheckMap.lean:334` lists the retired `build-math-view.mjs` as a sample path (harmless, not existence-checked).
- PLAN.md is ~1,410 lines (limit ~1,300); line cuts wait for rev 12.
- The `math-to-lean.html` lessons data (generated from research lessons.json) keeps one note on kickoff-sketch docstrings.

Read first: PLAN §5.3 and Appendix A41.
