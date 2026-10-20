# Handoff: latex-plan-text

State: branch `worktree-wf_1de700b0-a77-2`, commits on top of main 89eb170d (see `git log main..HEAD`).

## Done
- `docs/plan/PLAN.md` rev 11.3 "math in artifacts": frontmatter revision and date, intro rev line, §0, §1.2 V-s,
  §3.1 diagram (math pages node), §5.1 M0 (axiom check), §5.3 rewritten (four steps per math-artifact.md, rows at
  the current `stmtHash`, old counts as history), §5.4 TL0, §7.1 (`math.lock.json` dropped), §8.2 roster, §8.5
  (`math:sign` dropped), §10.2 C4 note, §10.7 (`mathview-differential` retired), R6, R24, §12.0, Q25/Q28, A41, App D.
- `docs/plan/math-view.html` removed (A41: new rule (rev 11.3): a page whose generator is retired is removed).
- `docs/plan/loop-plan.html`: Math section rewritten, decision row, Q25, M0 rows, roster, commands, footer rev 11.3.
- `docs/plan/math-to-lean.html`: back-link text, one sentence on where the math column comes from.

- Round 2 (review of 93320da8): C4 "Must be true" (PLAN §10.2 and loop-plan.html) = every math row the report
  shows is `agree` at the current `stmtHash`; A41 wording "New rule (rev 11.3)"; §5.3 cites `Verdict.lean:48, 57-61`;
  loop-plan.html Lean example captioned as an illustrative kickoff sketch (not reviewed math); math-to-lean.html
  names its math source (kickoff sketch, two passes, lessons.json). Logged in PLAN App D rev 11.3.
- Round 3 (final design round): loop-plan.html Lean example (explainer v1, 9a29a9dc) removed; no math block remains on loop-plan.html.

## Verified (round 3)
- `check-lean-lessons.mjs --check`, `node --test scripts/ci-paths.test.mjs`, `ci-paths --check` green; every
  relative href in loop-plan.html and math-to-lean.html resolves.

## Open (other owners)
- Follow-up: add reviewed math rows to loop-plan.html (Fw.Verdict.better_sound, Fw.Null.land_null_prob) per math-artifact.md.
- `lean/Fw/Ops/CheckMap.lean:334` lists the retired `build-math-view.mjs` as a sample path (harmless, not existence-checked).
- PLAN.md is ~1,410 lines (limit ~1,300); line cuts wait for rev 12.
- The `math-to-lean.html` lessons data (generated from research lessons.json) keeps one note on kickoff-sketch docstrings.

Read first: PLAN §5.3 and Appendix A41.
