# run-cite-roles (console-builder) handoff

State: branch worktree-wf_e007c264-660-3 (round 2); `sh lean/scripts/check.sh` green; root `pnpm test` runs the node test.
- Lean `Fw.Gate.RunCite`: `Role` (row | aa | sibling f) and `judge` (judge_row, judge_aa, judge_sibling); evidence
  parse `mentions`/`citesOf` (cite_marked, cite_row). Round 2: a row with no `flag` cites only its marked runs
  (row_no_flag, row_flag), every other run id is in `unmarked`/`unflagged` (row_no_flag_covers, mem_unflagged).
- Golden run-cite.jsonl: 20 cases; wire line `rc-1`. The gh cwd test calls from another cwd; fails without `cwd: top`.
Ledger edits for the lead (`research/findings/ledger.json`, `evidence` only, no new field; each old text occurs once
in its row; replace old with new as written):
1. morph.tween.waapi.falsified and morph.tween.waapiScoped.falsified: "A/A 39466378530" -> "A/A run 39466378530 (A/A)"
2. morph.tween.waapi.falsified: "waapi-scoped runs 39457767229, 39462241403, 39472304195" -> "waapi-scoped runs 39457767229 (morph.tween:waapi-scoped), 39462241403 (morph.tween:waapi-scoped), 39472304195 (morph.tween:waapi-scoped)"
3. morph.tween.waapiScoped.falsified: "waapi runs 39449092483, 39453458295, 39471466367" -> "waapi runs 39449092483 (morph.tween:waapi), 39453458295 (morph.tween:waapi), 39471466367 (morph.tween:waapi)"
4. morph.tween.waapiScoped.falsified: "(run 39412301221:" -> "(run 39412301221 (morph.tween:waapi):"
5. nav.earn.noTransition: "39464294630 and 39464322751 (A/A)" -> "39464294630 (A/A) and 39464322751 (A/A)"
6. hero.exit.scoped.inline: "runs 39448209903, 39452631146 (hero.exit:scoped)" -> "runs 39448209903 (hero.exit:scoped), 39452631146 (hero.exit:scoped)"
7. hero.exit.scoped.inline: "39456741492 (hero.exit:faithful A/A)" -> "39456741492 (hero.exit:faithful), a faithful A/A,"
8. hero.exit.scoped.inline: "and 39466179818 at 45a40e7b" -> "and 39466179818 (hero.exit:scoped) at 45a40e7b"
9. hero.exit.scoped.inline: "its A/A run 39472217441" -> "its faithful A/A run 39472217441 (hero.exit:faithful)"
10. hero.exit.scoped.inline: "chromium-counts runs 39461009752, 39462188464;" -> "chromium-counts runs 39461009752 (hero.exit:scoped), 39462188464 (A/A);"
11. hero.exit.scoped.inline: "39514533027, 39514585897, 39514619612, 39515982760, 39516056860 (hero.exit:scoped)" -> "39514533027 (hero.exit:scoped), 39514585897 (hero.exit:scoped), 39514619612 (hero.exit:scoped), 39515982760 (hero.exit:scoped), 39516056860 (hero.exit:scoped)"
12. hero.exit.scoped.inline: "39514655614, 39514696773, 39514734504, 39516021307, 39516092834 (hero.exit:faithful A/A)" -> "39514655614 (hero.exit:faithful), 39514696773 (hero.exit:faithful), 39514734504 (hero.exit:faithful), 39516021307 (hero.exit:faithful), 39516092834 (hero.exit:faithful), the faithful A/A"
Why: 7, 9, 12: those "faithful A/A" runs carried `?fw=hero.exit:faithful`. 10: research/notes/2026/10-20-exit-scoped-inline.md:166
calls 39462188464 the default (faithful) run (39461009752 is its `?fw=hero.exit:scoped` arm); its arms carried no query (MEASURED).
Verified (MEASURED, 2026-10-21, 37 runs downloaded once): temp copy of this branch with edits 1-12 applied: run-cite
46 citations, match 46, mismatch 0, unknown 0, unflagged 0 (exit 0); preset regenerated (`Fw.Preset.Gen.run []`):
no file changed (`v2-proved: written, 0 flags`); `sh lean/scripts/check.sh` exit 0. No preset file to commit with the
ledger. Main ledger as is: mismatch 10, 1 unflagged row (15 unmarked ids), exit 1.
Open: `--note` citations carry no role, parsed in JS (`noteCites`, TS stand-in); run ids outside `evidence` (28 of 72
rows) are unchecked (accepted limit). Writes outside the graph: lean/golden/wire-{requests,replies}.txt (round 1).
Read first: docs/team/tools/run-cite.md (marker rules), then `rowCites` and `citesOf` in lean/Fw/Gate/RunCite.lean.
