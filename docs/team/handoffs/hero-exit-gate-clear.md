# hero-exit-gate-clear handoff

- Branch: worktree-wf_aba1dc22-976-1 (CI branch ci/hero-exit-gate-clear); worktree .claude/worktrees/wf_aba1dc22-976-1 of the main checkout
- Last code commit: see `git log -1`. CI pushes used: 3 of 3 (2695eef4f, 2cfe05e58, 559c2e728); no more.
- CI runs (trajectory-probe, `fw=hero.exit:threaded`): 40668662980 complete (chromium hero pass, morph pass; linux-webkit hero pass); 40671695274 complete (mac hero pass, mac morph no verdict: coverage, noise); 40674554372 complete (linux and mac hero pass, mac morph pass). Lean runs 40668662965, 40671695266 success.
- Recorded all three with Gen.record; Gen.merge is newest-run-wins per (flags, engine, walk). Entry: gate chromium and gate webkit met, blocker left `proofs` (ledger row n 6, out of the unit).
- Verified: Lean Fw.Gate.Consumer and Gen.merge theorems; gate-breakpoints tests 829 pass, contracts, runner land-inputs, ci-paths tests pass (through fw slot).
- Done: note research/notes/2026/10-2x-hero-exit-gate-clear.md, ledger note. Open: check.sh on the clean tree, plan lint, dry land, fw review ready.
- Read first: lean/Fw/Gate/Consumer.lean, packages/gate-breakpoints/src/trajectory/consumer.mjs, Gen.merge in lean/Fw/Preset/Gen.lean.
