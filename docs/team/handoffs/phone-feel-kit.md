# Handoff: phone-feel-kit

- Branch `worktree-wf_a4f669cd-67c-1`; worktree `.claude/worktrees/wf_a4f669cd-67c-1`; last code commit 9b8b96eac (this handoff is the commit after it).
- CI runs: none (the kit needs the phone; no push).
- Read first: `research/notes/2026/10-29-phone-feel-kit.md` (kit, dry-run table, lead commands, limits).

## State
- Lean: `lean/Fw/Device/Feel.lean` (order, cell, reducer, theorems), generator `lean/Fw/Device/FeelGolden.lean` +
  `lean/scripts/FeelGolden.lean`, golden `packages/contracts/golden/device/feel.jsonl`, wired in `lean/scripts/check.sh`,
  `lean/Fw/Ci/Trigger.lean`, `packages/contracts/golden/ci/triggers.jsonl`.
- TS: `packages/measure-webkit/src/device-feel.mjs` (pure, follows the golden), `device-feel-run.mjs` (glue),
  `device-cli.mjs feel start|next|rate|status|stop`, tests `test/device-feel*.test.mjs`.

## Verified
- check.sh green; measure-webkit tests 1007/1007; `scripts/ci-paths.test.mjs` 56/56; runner land-inputs 73/73.
- Phone dry run (one device run): Serious held for all 10 arms, every arm hydrated with the expected configHash and
  `?fw=` applied, pin cleared after stop (Nominal before, Fair after, end `cleared`), no process of mine left.

## Open
- The stop reply defect (control server closed before the reply) is fixed and unit-tested, not re-run on the phone.
- The feel verdict comes from the user via the lead; seed per session must differ (A is first and last).
- TS stand-ins of Feel.lean: `cellOf`, `reduceArm`, `reduceLook`, `scoresOf`, `orderOf` (golden-checked).
- `kill -9` of the session leaves the pin set; `feel start` or `pin-stop --dir` recovers it.
- The arms are not built in git: build them with the command in the note (`apps/site/dist/aot` is untracked).
