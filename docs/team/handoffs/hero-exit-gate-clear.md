# hero-exit-gate-clear handoff

- Branch: worktree-wf_aba1dc22-976-1 (CI branch ci/hero-exit-gate-clear); worktree .claude/worktrees/wf_aba1dc22-976-1 of the main checkout
- Last commit: 2695eef4f (push 1 of 3: trajectory-probe, `fw=hero.exit:threaded engines=both`, Chromium + Linux WebKit; macOS WebKit does not run on a plain push)
- CI runs: push 1 pending (run id to fill)
- Verified: Lean `Fw.Gate.Consumer` compiles; node tests consumer/hero-exit-offset/trajectory green.
- Open: macOS WebKit gate (needs `debug=nav-transition` on a push, or a lead dispatch), record + Gen.run, note, ledger, check.sh, dry land.
- Read first: lean/Fw/Gate/Consumer.lean, packages/gate-breakpoints/src/trajectory/consumer.mjs.
