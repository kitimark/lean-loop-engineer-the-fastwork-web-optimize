# park-attrib handoff
Branch: worktree-wf_e8ba3c22-914-1 (CI branch ci/park-attrib). Worktree: .claude/worktrees/wf_e8ba3c22-914-1 (under the main checkout)
Last commit: 72d0bfd91 (request commit on top of the gate build config commit).

## CI runs
- gate push 1 (?fw=engine.scroll:unthrottle,hero.exit:threaded, commit 72d0bfd91): run id pending, state running.
- gate push 2 (only if push 1 passes webkit: ?fw=engine.scroll:unthrottle,hero.exit:threaded-park): not pushed.

## Verified
- Lean rule lean/Fw/Ops/Attrib.lean (verdict: same commit, exactly one differing part, else notAttributable), goldens
  packages/contracts/golden/ops/attrib.jsonl via lean/Fw/Ops/AttribGolden.lean; check.sh job "attrib golden check"; trigger row added.
## Open
- both gate runs, the note research/notes/2026/10-31-park-attrib.md, ledger row hero.exit:threaded-park, workflow revert, check.sh, dry land, review ready.
