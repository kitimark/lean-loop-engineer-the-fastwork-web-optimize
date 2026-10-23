# chrome-balance-repro handoff

- Branch: worktree-wf_15096bff-386-1 (CI branch ci/chrome-balance-repro)
- Worktree: .claude/worktrees/wf_15096bff-386-1
- Last commit: 90bf4ab (probe pushed); see `git log -1`
- Pushes and dispatches: 1 push + 1 dispatch of 4.

## CI runs
| run | what | state |
|---|---|---|
| (nonce e2a53ac9086cc631) | chromium-counts, profile balance-repro, target original, runs 2 | running |

## Verified
- Nothing measured yet.

## Open
- Read the run: `PROBE <id> <status>` lines per variant in each counts job log; rows in artifact `chromium-counts-original-r*`.
- Item (3): move crash-* and balance-repro to probes/, Lean `Fw/Measure/Profile.lean` (css, dropFlags, kind, UA) with golden.
- Item (2): desktop UA for `mobile: false` profiles (Lean decision).
- Note: research/notes/2026/10-2x-chrome-balance-repro.md.
