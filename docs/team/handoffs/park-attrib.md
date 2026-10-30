# park-attrib handoff
Branch: worktree-wf_e8ba3c22-914-1 (CI branch ci/park-attrib). Worktree: .claude/worktrees/wf_e8ba3c22-914-1 (under the main checkout).
Last commit: see `git log -1`. Finisher round done; no CI push of my own in this round.

## CI runs
- 41078004214 breakpoint-gate push (72d0bfd91, ?fw=engine.scroll:unthrottle,hero.exit:threaded): complete; WebKit FAIL 147 readings.
- 41086902481 dispatch on main at 31fdd85b6, flags none: complete; chromium pass, playwright-webkit pass (6765 pass, 0 fail, 291 excused).
- 41087718575 dispatch on main at 31fdd85b6, ?fw=hero.exit:threaded only: complete; chromium pass, playwright-webkit FAIL (6618 pass, 147 fail, 291 excused, 17 cells not ok).

## Verified
- Same commit, flag-set difference of size 1: Lean `Fw.Ops.Attrib.verdict` = causedBy hero.exit (failing threaded, passing none); golden row 18 in
  packages/contracts/golden/ops/attrib.jsonl (generator lean/Fw/Ops/AttribGolden.lean, regenerated, --check clean).
- WebKit failing cells (hero.orbit 10 groups, hero.deck 7), items (card translate 1060 + 164) and table sha256 e524c0ee... equal run 41078004214.
- Note research/notes/2026/10-31-park-attrib.md sections 2-5; ledger rows hero.exit.threaded-park and hero.exit:threaded (n 6) updated in research/findings/ledger.json.
## Open
- Preset decision for hero.exit:threaded (in v2-proved and shipped; preset entry d6174ba8c, 2026-10-29, had no breakpoint-gate run): the user's, no flag or preset change here.
- Why WebKit computes the sub-pixel card translate: INFERRED, not read from source (follow-up).
## Conventions
- BSD sed needs `sed -i ''`; lean goldens run from lean/ (`lake build Fw.Ops.AttribGolden` first, then gen via lake env lean --stdin); pnpm install --offline --frozen-lockfile in a fresh worktree.
