# hero-exit-gate-clear handoff

- Branch: worktree-wf_aba1dc22-976-1 (CI branch ci/hero-exit-gate-clear); worktree .claude/worktrees/wf_aba1dc22-976-1 of the main checkout
- Last code commit: 2695eef4f (push 1). Push 2 (macOS WebKit, `debug=nav-transition engines=playwright-webkit`) follows.
- CI runs: 40668662980 (push 1, trajectory-probe, `fw=hero.exit:threaded engines=both`, sha 2695eef4f) complete: Chromium hero CLEAN (0 hero fails; the box bits show orbit no-box at 390, deck no-box at 640+), Linux WebKit hero CLEAN 0 fail; Chromium morph has 1 new unit (nav.rect close@0 at 1280), one width only.
- Lean run 40668662965 success. check.sh green locally through fw slot.
- Verified: Lean `Fw.Gate.Consumer` (theorems, golden gate/consumer.jsonl); node tests consumer/hero-exit-offset/trajectory green.
- Open: macOS WebKit run (push 2), record (Gen.record) + Gen.run; the stored old failing rows of run 40156078840 stay a fail in `tcell` (own fail first) unless Gen.merge supersedes them; note, ledger note, dry land.
- Read first: lean/Fw/Gate/Consumer.lean, packages/gate-breakpoints/src/trajectory/consumer.mjs.
