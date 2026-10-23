branch: worktree-wf_3bba9083-6b9-1 (CI branch ci/chrome-crash-platforms)
worktree: .claude/worktrees/wf_3bba9083-6b9-1 (inside the main checkout)
last commit: a4eaaafe0 (4 pushes + 2 dispatches = 6 used; note and final commit pending)
CI runs (all complete, all at a4eaaafe0 except the first three): 39889986847, 39890929696, 39892378128, 39893655746 (push 4), 39894690177 and 39894741675 (dispatches). Result: no crash with system fonts on any native leg (linux x64 headless/xvfb, arm64 control, windows, macOS canary/stable); empty fonts.conf: linux x64 headless, x64 xvfb and arm64 crash SIGSEGV 0x84 on min and page 4/4, ok at 860 and wrap; macOS later CfT builds stall at Page.navigate (harness, not a crash)
verified: ci-paths 54, runner land tests 62, measure-chromium 70, lean check.sh green at 969ad734e (re-run at final commit pending), actionlint clean
open: final commit, merge main check, dry land, review ready, user step: file the Chromium bug (now: only without system fonts)

What this task adds
- Lean `Fw.Measure.Profile`: Mode, runnable (a probe is refused in counts mode), readOk (probes/ vs profiles/), cftPlatform/cftUrl (CfT platform map); JS twins in packages/measure-chromium/src/profile.mjs; golden profile.jsonl.
- Lane: src/run.mjs exits 2 for kind probe in counts mode; src/host.mjs and chromium-counts.yml read probes/; src/crash-probe.mjs runs a probe (any platform).
- Native workflow .github/workflows/chrome-crash-probe.yml (8 legs on free runners), probe packages/measure-chromium/probes/balance-platforms.json.
- Excluded from pool caps: chrome-crash-probe.yml (Lean Fw.Ci.Pool.Caps.excluded) because runs-on is a matrix expression.

Conventions: push with `git branch -f ci/chrome-crash-platforms HEAD` then plain `git push origin ci/chrome-crash-platforms`; head commit message needs `[ci:chrome-crash-probe]`; wait with `pnpm -s fw ci wait --branch ci/chrome-crash-platforms --workflow chrome-crash-probe`.
Read first: research/notes/2026/10-2x-chrome-balance-repro.md, packages/measure-chromium/probes/README.md.
Local debug note: loopback http navigation failed in the tool sandbox on the Mac, so the probe code was only checked on CI.
