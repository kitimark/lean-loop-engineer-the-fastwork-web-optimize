# hero-exit-q6 handoff

- Branch `worktree-wf_2943a5a2-21f-1`, worktree `.claude/worktrees/wf_2943a5a2-21f-1`.
- Last work commit: the commit that adds this line (`git log -1 worktree-wf_2943a5a2-21f-1`); before it, 5af11fc8e (merge of main eda627b3d, review round).
- CI runs: none dispatched. Data run 40156078840 (at fbca417): lead dispatch on main, state complete, conclusion
  success; its hero-path verdict is the measured 25/40/40 trajectory failure this task explains.
- Verified: `sh lean/scripts/check.sh` green through fw slot (exit offset golden, 136 lines; v2-proved up to date);
  gate-breakpoints tests 781/781; contracts 11/11; ci-paths 56/56; runner land-inputs 73/73.
- Open: the reducer adopts `judgedEqual`; the gate blockers need the hidden-consumer rule or a probe re-run;
  ledger row n 6 promotion (`partly-proved` → `proved`) is the lead's call.

## State
- `lean/Fw/Parts/HeroExitScrollOffset.lean`: per-frame age model (`threadedAge`, `origAge`), `threaded_never_older`,
  `threaded_older_iff` (WebKit main thread, in-frame script scroll), `arms_equal_at_rest`, probe model
  (`judgedNow`, `judgedEqual`), measured table of run 40156078840 with `measured_counts` 25/40/40 and `measured_hidden`.
- `lean/Fw/Preset/Gen.lean`: `q6Answer := some q6Text`; link `hero.exit:threaded` → `threadedKey`;
  `threaded_proofs_iff`, `threaded_proofs_blocked`, `threaded_proofs_of_promoted`, `threaded_not_yet`.
- Gen.entry for hero.exit:threaded: not yet, blockers proofs, gate chromium, gate webkit. v2-proved stays
  [engine.scroll:unthrottle].
- Golden `packages/contracts/golden/parts/hero-exit-offset.jsonl`, replayed by
  `packages/gate-breakpoints/test/hero-exit-offset.test.mjs`.

## Conventions
- Regenerate goldens only from Lean: `HeroExitScrollOffset.gen`, `Gen.run` (drop `--check` to write).
- Worktree needs `pnpm install --offline --frozen-lockfile` before package tests.

## Read first
- `research/notes/2026/10-2x-hero-exit-q6.md`, then the Lean module above.
