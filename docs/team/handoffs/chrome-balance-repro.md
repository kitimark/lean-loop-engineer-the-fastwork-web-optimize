# chrome-balance-repro handoff

- Branch: worktree-wf_15096bff-386-1 (CI branch ci/chrome-balance-repro)
- Worktree: .claude/worktrees/wf_15096bff-386-1
- Last commit: the branch head (probe pushed at 90bf4ab)
- Pushes and dispatches: 1 push + 1 dispatch of 4.

## CI runs
| run | what | state |
|---|---|---|
| 39878812594 | chromium-counts, profile balance-repro, target original, runs 2 | done: counts r1, r2 green; classify fails by design (a probe records no counts) |

## Verified
- MEASURED 39878812594 (r1 = r2): stock Chrome for Testing linux-arm64 156.0.8078.4, 156.0.8078.47, 157.0.8103.15 and
  158.0.8118.0 (new headless, no BeginFrameControl) crash SIGSEGV 0x84 on the minimal repro and on the original page at 1280;
  ok at 860, with h2 `text-wrap: wrap` or `nowrap`, with the o as inline-block. `white-space: nowrap`, `.c` block, `.w` inline
  and an empty o still crash.

## Open
- Item (3): move crash-* and balance-repro to probes/, Lean `Fw/Measure/Profile.lean` (css, dropFlags, kind, UA) with golden.
- Item (2): desktop UA for `mobile: false` profiles (Lean decision).
- Note: research/notes/2026/10-2x-chrome-balance-repro.md.
