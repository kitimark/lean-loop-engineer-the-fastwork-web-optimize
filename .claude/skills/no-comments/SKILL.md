---
name: no-comments
description: Lead runs this before review of code in TS, JS, shell, YAML or Lean: spawns comment-sicko on the scope, judges its findings, fixes accepted ones at the root and offers to encode constraint comments as a type, Lean theorem, test or lint.
disable-model-invocation: true
---

# No comments

Spawn `comment-sicko` and act on the findings you accept. Its keep list and Lean rules live in
`.claude/agents/comment-sicko.md`; do not restate them. Write new code so it would delete nothing. Defer to its fresh
view: you wrote the code it reviews.

Adapted from cursor/plugins pstack (MIT, (c) 2026 Lauren Tan), commit d457567

## Scope

The caller's files or diff. Otherwise the diff against `main`, working tree included (`git diff main`).

## Steps

1. Spawn it with the Agent tool: `subagent_type: "comment-sicko"`, no `name` (an unnamed lead spawn, like `patcher`), the scope as paths or a diff range. Pass
   no `model` (sizing: `docs/team/token-policy.md`). It edits comments, so only the lead spawns it. A role names its
   scope in its report and the lead runs this skill before the land.
2. Read its report and `git diff`. Reject code edits, files outside the scope, deleted keep-list comments, a `MUST
   KILL` with a wrong reason, and flags on code we keep on purpose. A MUST KILL on our own surprising code stays actionable; never restore its comment. A suppression of a correctness or safety rule stays a MUST KILL. A keep survives only with proof that it is about
   code we cannot change. Check the scope for suppressions it missed. Before you accept a thin `IMPORTANT` or `do not
   remove` kill or keep, read the named symbol and its callers (`scout` for a sweep over 8 KB). An ambiguous kill
   stays deleted. A refuted or ambiguous keep is deleted. Revert and rerun once a rejected report with the failure
   named. Report a second rejection open.
3. Fix trivial accepted flags directly: delete the dead path, drop the parameter, call the real API. If a fix needs a
   new shape, write one design note (at most 10 lines, in your report or handoff) for the accepted set first.
4. Make the smallest root-cause fix in scope and remove every named workaround. If the root cause lies outside the
   scope, land the in-scope part and report the rest open. Never add a guard that hides the symptom.
5. A constraint comment (`do not remove`, `do not change`, `ask X first`) about our own code: offer the cheapest
   in-scope encoding, a type, a Lean theorem or `#guard`, a test or a CI lint. Wait for a yes from the lead or the
   user (a workflow prompt may give it in advance). Yes: encode it, then delete the comment. No: delete it and report
   the constraint open.
6. Report counts: deleted, restored, reruns, fixes, encodings offered and done, constraints left unenforced, other open
   work.
