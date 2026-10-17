---
id: 2026-10-17-spk-o
kind: note
title: "SPK-o: can a named worktree subagent run fw gate, git add -- and git commit with zero isolation refusals?"
status: draft
created: 2026-10-17
topics: [spike, decision-record, worktree, isolation, sandbox]
---

# SPK-o (DRAFT decision record)

**Question (PLAN Appendix B).** Can a named `isolation: "worktree"` subagent run `pnpm fw gate --part x`,
`git add -- p` and `git commit -m` with zero isolation refusals?

**Status: PARTIAL.** `git add`/`git commit` work, but "zero refusals" does not hold; `fw gate` does not exist yet.

**Answer so far.**
- Plain `git add -- <paths>` and `git commit -m` succeed (36 commit commands without error in worktree agents).
- Refusals happen for **compound or computed forms**: a command that changes directory to a location computed at run
  time, `git -C <abs path> ...`, a command chaining `git status && git add ...`, a multi-line `sed -i`, and env-prefixed
  commands naming `git` in a form the checker cannot verify.
- In 28 worktree agents, **138 of 1,652 Bash results (8.4 %)** were "This agent is isolated in the worktree ...
  too complex to verify". 76 of the 138 start with `cd <absolute worktree path>`.
- `pnpm fw gate` is not implemented (`apps/runner/src/` has `card.ts`, `fw.ts`, `land.ts`, `lib.ts`; no `gate`).

## Evidence
| Claim | Evidence | Status |
|---|---|---|
| 1,652 Bash tool results in 28 worktree-spawned agents; 138 contain "isolated in the worktree" | scan of `<session>/subagents/agent-*.jsonl` for agents with `spawnedWithWorktree` | MEASURED |
| 36 `git commit` commands ran without an error result; 7 `commit`-containing commands errored (6 isolation refusals in console-deflake, lean-null-fix x2, part-fix, site-aot, console-lean; 1 `rebase` note with exit 1 after "Successfully rebased") | same | MEASURED |
| Refusal reasons seen: "too complex to verify that it stays inside the worktree", "changes directory to a location computed at run time", "names git in a form too complex to verify" | same | MEASURED |
| Earlier profile count: 101 isolation errors of 213 errors | `research/notes/2026/10-17-agent-observability-sources.md` §1 @b65e983 | MEASURED (earlier snapshot) |
| v1: 3,046 isolation refusals, 57 % of all errors | PLAN §8.3 line ~1080, [08] | CONFIRMED (v1 digest) |
| Land path: `fw land` is the only way to main; branch `card/<CARD>` rules | `docs/team/handoffs/con-land.md` @840f7d6 | CONFIRMED |
| `fw gate` absent | `apps/runner/src/*.ts` at HEAD `30e3264` | CONFIRMED |

**Evidence commit:** `840f7d6` (fw land/card), `b65e983` (observability note); HEAD `30e3264`.

## Missing
- `pnpm fw gate --part x` (gate board W2-7); the third leg of the test cannot run until it exists.
- The test as the PLAN states it: a **fresh** named worktree subagent running exactly the three commands, as single plain
  commands, with the sandbox of SPK-t on. The numbers above come from real work, not that test.

## Next step
1. Owner: console-builder. Add the rule to every code-editing role file and to `CLAUDE.md`: one plain command per call;
   no `cd <computed path>` (the worktree is the cwd); no `git -C`; no `&&`-chains around `git add`/`git commit`.
   Add a PostToolUseFailure counter for "isolated in the worktree" so the stall watcher flags repeats.
2. Owner: console-builder after `fw gate` lands: spawn one named worktree subagent with a script of the three commands;
   pass = 0 refusals; record here and in SPK-t.

## What this changes in the plan
- §8.3: change "zero refusals" from an expectation to a rule plus a measured baseline (8.4 % of Bash calls refused in
  this session). Appendix B: SPK-o "partial".
