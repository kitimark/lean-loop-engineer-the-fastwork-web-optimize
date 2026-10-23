branch: worktree-wf_3bba9083-6b9-1 (CI branch ci/chrome-crash-platforms)
worktree: .claude/worktrees/wf_3bba9083-6b9-1 (inside the main checkout)
last commit: 57613fb3c (3 pushes used; push 4 adds platform fonts of the title, then 2 dispatches of the same code)
CI runs: 39889986847 (push 1), 39890929696 (push 2), 39892378128 (push 3, 57613fb3c): all complete. Result: with the runner system fonts no native leg crashes (linux x64 headless/xvfb, arm64 control, windows, macOS stable+canary); with the container empty fonts.conf linux x64 headless, x64 xvfb and arm64 crash (SIGSEGV 0x84) on min and page at 1280, ok at 860 and with text-wrap wrap. macOS: only the first CfT build per job loads (later ones stall at Page.navigate)
verified: local tests only (ci-paths 54 pass, land-inputs + land-overflow-widths 62 pass, profile.test 9 pass); no platform result yet
open: platform rows (linux x64 headless/xvfb, macOS arm64/x64, Windows), note, dry land, review ready

What this task adds
- Lean `Fw.Measure.Profile`: Mode, runnable (a probe is refused in counts mode), readOk (probes/ vs profiles/), cftPlatform/cftUrl (CfT platform map); JS twins in packages/measure-chromium/src/profile.mjs; golden profile.jsonl.
- Lane: src/run.mjs exits 2 for kind probe in counts mode; src/host.mjs and chromium-counts.yml read probes/; src/crash-probe.mjs runs a probe (any platform).
- Native workflow .github/workflows/chrome-crash-probe.yml (8 legs on free runners), probe packages/measure-chromium/probes/balance-platforms.json.
- Excluded from pool caps: chrome-crash-probe.yml (Lean Fw.Ci.Pool.Caps.excluded) because runs-on is a matrix expression.

Conventions: push with `git branch -f ci/chrome-crash-platforms HEAD` then plain `git push origin ci/chrome-crash-platforms`; head commit message needs `[ci:chrome-crash-probe]`; wait with `pnpm -s fw ci wait --branch ci/chrome-crash-platforms --workflow chrome-crash-probe`.
Read first: research/notes/2026/10-2x-chrome-balance-repro.md, packages/measure-chromium/probes/README.md.
Local debug note: loopback http navigation failed in the tool sandbox on the Mac, so the probe code was only checked on CI.
