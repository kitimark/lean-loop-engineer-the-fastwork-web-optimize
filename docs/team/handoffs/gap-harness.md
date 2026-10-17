# gap-harness handoff

State: branch `worktree-wf_beb42b80-cec-3` (commit in the report). Lane `gaps` in `packages/gate-breakpoints`
(`src/gaps/**`; wiring in `src/cli.mjs`, `src/run.mjs`, `src/summary.mjs`; tests `test/gaps.test.mjs`, 25 pass).
Results: `packages/gate-breakpoints/results/gaps/gaps.{json,md}` (run twice, byte-identical).

Read first: `packages/gate-breakpoints/src/gaps/README.md`, then `src/gaps/DEVICE.md` (phone session).

Result: all 8 cells (4 fractional widths, 4 hover x pointer crosses) pass on Chromium 155 (zoom 200% profile pref +
CDP override 2N+1 for fractions; `--blink-settings` for crosses). On WebKit all 8 are `unreachable` with evidence
(Playwright WebKit, macOS WKWebView page zoom, iPhone and iPad iOS 27.0 Simulator): media width always whole, primary
pair only (hover,fine) or (none,coarse).

Conventions: new verdict state `unreachable` (not NC) only when the mechanism table says unreachable AND every record
shows it. Default gate run unchanged (byte-identical to HEAD). No device ids, LAN addresses or home paths in files.
Sim-lock pid is the caller's PPID: acquire, run, release in one shell command.

Not run: the real-phone session (`gaps device-serve`, then `device-judge`; pass = W, X, S, L ok).

Open items:
- Lean: specify `webkitPrimaryPairs`, the WebKit whole-width fact, the `unreachable` verdict state; change the
  fractional probes to dpr 2 (today TS `realizeEnv` maps dpr 5/4 to dpr 2 + zoom 2).
- TS stand-ins to retire: `realizeEnv`, `WEBKIT_PRIMARY_PAIRS`, mechanism table, `judge.mjs` evidence checks,
  `devicejudge.mjs`.
- Chromium compares with 1/64 slack; the .5 widths are far from that edge, but note it in the Lean spec.
- iPad Simulator width 1032 has no Lean vector (informative only).
- aA page zoom was not driven in the Simulator (no UI automation): source plus macOS pageZoom cover it; the phone
  session covers it for real.
- Wire the lane into CI (it needs Chromium, Playwright WebKit, macOS host with the Simulator).
