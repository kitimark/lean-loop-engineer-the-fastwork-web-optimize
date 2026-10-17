# Handoff: plan-rev9 (plan-editor, Fable)

**State.** PLAN revision 9 written in worktree branch `worktree-agent-a09dbbfc73afd86d3` (commit: see `git log -1 --grep 'Task: plan-rev9'`). Base: ad5eeea. Not merged to `main`; the lead lands it.

**What moved.** The experiment ends with a report by 2026-10-20 13:15 +0700 (user decision 2026-10-17 23:13 +0700; first commit 931aa35 at 13:15:05). PLAN.md: 1,537 → 1,313 lines; new §10 (minimum experiment, checkpoints C1 T+12h / C2 T+24h / C3 T+48h / C4 T+62h, user actions, cut list), Q36 shells, Q37 uncalibrated model, R34 deadline, R35 shells, A29-A31 conflicts, MX and T+Nh glossary rows, App C folded into Q17, App D rev 9 entry. work-graph.json: milestone MX (cut), M1-M6 retitled, 9 tasks cut (`CUT (rev 9):` prefix, deps cleared), 3 conditional on `webkit-gonogo`, 6 added (`webkit-gonogo`, `zone-baseline-lean`, `shells`, `port-morph`, `phone-session-2`, `math-final`), deps re-wired, top-level `deadline` (tolerated: Lean and TS read only `milestones`/`tasks`). loop-plan.html: `#rev9` section replaces `#rev7`, roadmap lede, decisions rows, footer; the generated math view is byte-identical.

**Conventions.** Sections replaced whole with a splice script keyed on heading prefixes (scratchpad, not committed); claims keep CONFIRMED / INFERRED / MEASURED; every new label has a glossary row; no personal data; commit trailer `Task: plan-rev9`.

**Self-check.** `node -e JSON.parse` on work-graph.json; every dep and milestone id resolves; PLAN.md has no `§12.3`, no dangling Appendix C, cut task names appear only in cut context; math view unchanged.

**Open.** (1) Q34-Q37 default at 2026-10-18 11:15 if unanswered. (2) `webkit-gonogo` is a lead decision at C1, not a build task. (3) `zone-baseline-lean` and `shells` carry guessed `writes` globs; the lead may tighten them. (4) `pnpm fw plan sync` has not been run on the new graph (console state is the lead's). (5) PLAN is 1,313 lines, 13 over the soft cap; §11 R1-R20 is the next place to trim.

**Read first.** `docs/plan/PLAN.md` §0, §10, §12.1; Appendix D (rev 9 entry); `docs/team/work-graph.json` `deadline` and milestone MX.
