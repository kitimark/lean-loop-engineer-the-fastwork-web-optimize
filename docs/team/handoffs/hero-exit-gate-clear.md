# hero-exit-gate-clear handoff

- Branch: worktree-wf_aba1dc22-976-1 (CI branch ci/hero-exit-gate-clear); worktree .claude/worktrees/wf_aba1dc22-976-1 of the main checkout
- Last code commit: see `git log -1`; push 3 (mac retry, same probe line) follows this commit. Pushes used: 2 of 3 (2695eef4f, 2cfe05e58), the 3rd is this commit.
- CI runs: 40668662980 (push 1, trajectory-probe, `fw=hero.exit:threaded engines=both`) complete: Chromium hero pass, morph pass; Linux WebKit hero pass. 40671695274 (push 2, `engines=playwright-webkit debug=nav-transition`) complete: linux-webkit hero pass, mac-webkit hero pass (0 fail), mac-webkit morph "no verdict: coverage" (nav close@8 at 390 and open@3 at 641, single steps missing; the A/A arm has the same at 640 and 1280). Lean runs 40668662965 and 40671695266 success.
- Recorded (Gen.record) runs 40668662980 and 40671695274 into v2-proved.trajectory.jsonl; Gen.merge now newest-run-wins per (flags, engine, walk), which supersedes the failing rows of run 40156078840. Entry: gate chromium met; gate webkit pending on mac morph coverage.
- Verified: Lean Fw.Gate.Consumer (theorems, golden gate/consumer.jsonl); Gen.merge theorems and guards; gate-breakpoints tests 829 pass, contracts tests pass (through fw slot).
- Open: run of push 3, record it, regenerate decisions, note research/notes/2026/10-2x-hero-exit-gate-clear.md, ledger note, check.sh, plan lint, dry land, fw review ready. `proofs` (ledger row n 6) stays.
- Read first: lean/Fw/Gate/Consumer.lean, packages/gate-breakpoints/src/trajectory/consumer.mjs, Gen.merge in lean/Fw/Preset/Gen.lean.
