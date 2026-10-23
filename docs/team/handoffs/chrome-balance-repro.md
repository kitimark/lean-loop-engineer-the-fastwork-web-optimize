# chrome-balance-repro handoff

- Branch: worktree-wf_15096bff-386-1 (CI branch ci/chrome-balance-repro at 90bf4ab, the probe)
- Worktree: .claude/worktrees/wf_15096bff-386-1
- Last commit: the branch head (work at 9536f41f3 and 606bdf21a, this handoff after)
- Pushes and dispatches: 1 push + 1 dispatch of 4.

## CI runs
| run | what | state |
|---|---|---|
| 39878812594 | chromium-counts, profile balance-repro, target original, runs 2 | failed (conclusion failure): counts r1, r2 green and carry the result; classify fails because probe rows have no frames field |

## Verified
- MEASURED 39878812594 (r1 = r2): stock Chrome for Testing linux-arm64 156.0.8078.4, 156.0.8078.47, 157.0.8103.15 and
  158.0.8118.0 (new headless, no BeginFrameControl) crash SIGSEGV 0x84 on the minimal repro and on the original page at 1280;
  ok at 860, with h2 `text-wrap: wrap` or `nowrap`, with the o as inline-block. `white-space: nowrap`, `.c` block, `.w` inline
  and an empty o still crash.
- Lean `Fw/Measure/Profile.lean` compiles; golden `packages/contracts/golden/measure/profile.jsonl` (31 lines) --check ok;
  `test/profile.test.mjs` 7/7; `scripts/ci-paths.test.mjs` 54/54 (after the Trigger.lean row edit); runner land-inputs 56/56.

## Open
- Outside task writes: lean/Fw/Ci/Trigger.lean, packages/contracts/golden/ci/triggers.jsonl, lean/scripts/ProfileGolden.lean, lean/scripts/check.sh, packages/measure-chromium/src/profile.mjs, packages/measure-chromium/test/profile.test.mjs.
- Done: slot check.sh all green, measure-chromium 67/67, measure-webkit 402/402; main e5c3d523e merged; dry land
  `VERDICT dry chrome-balance-repro` needs `--allow lean/Fw/Ci/Trigger.lean` (the lean.yml row now lists the profile golden);
  review ready: `review`.
- Follow-ups: host.mjs, crash-probe.mjs and chromium-counts.yml read only `profiles/`; a probe runs by copying it there on a
  ci branch (probes/README.md). Rewrite people title fix (drop balance or o inline-block) is a new task. Filing the crbug is a
  user step (note has the text).

## Read first
research/notes/2026/10-2x-chrome-balance-repro.md, lean/Fw/Measure/Profile.lean, packages/measure-chromium/probes/README.md.
