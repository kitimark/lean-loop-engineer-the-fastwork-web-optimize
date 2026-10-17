# gap-harness handoff

State: branch `worktree-agent-a388a51aa92c1df58` (CI branch `ci/gap-harness`), last commits "Simulator arms on the slow CI
runner" and the results commit after it. Lane `gaps` of `packages/gate-breakpoints` (`src/gaps/**`, wiring in `src/cli.mjs`,
`src/run.mjs`, `src/summary.mjs`); tests `test/gaps.test.mjs` (14), whole package 32 pass (needs `FW_CORE_BIN`).
Read first: `src/gaps/README.md`, then `.github/workflows/gate-gaps.yml`, `src/gaps/DEVICE.md` (phone session).

CI (MEASURED): Linux job on push (paths filter) and dispatch; macOS job dispatch only (`-f macos=true`), 1 VM,
`max-parallel: 1`, timeout 40 (5 macOS slots shared). Runs 39040510729 (Linux), 39041179813 (Simulator arms timed out),
39042512691 and 39044573514 (iPhone full; iPad full only in the last). Results in `results/gaps/{linux,macos}/` are copies
of `gaps-judged` artifacts only (see its README); no local-Mac result is committed.
Result: Chromium 156 passes all 8 cells at Lean's env (dpr 2, zoom 2 + override 2N+1). WebKit (Apple and GLib): 8
`unreachable` (4 primary-pair, 4 whole-width), the reach model holds on every record. Simulator iPhone and iPad: meta
viewport 600.5/640.5/860.5/1000.5 rounds to 601/641/861/1001; iPad `aim=` keeps media 1032 (vv and inner rounded).

Conventions: every verdict comes from fwcore (`judge.mjs` only calls ops: `gate.reach`, `gate.state`, `gate.tally`).
Collect jobs judge nothing; the `judge` job builds fwcore. No personal data or paths in committed files.

TS stand-ins (no decision logic beyond these): the `touchArm` conjunction in check T (`none/coarse` and `wLe1200` of the Lean
vector); mapping reach-model results to equal/differ/missing; record comparisons in checks S and X (`devicejudge.mjs`).

Open items:
- The real-phone session (`gaps device-serve`, then `device-judge` with the CI `evidence.json`) was NOT run; only the user's
  booked session may run it (pass = W, X, T, S, L).
- Lean could own T, S and X record comparisons; the iPad width 1032 has no Lean vector (informative).
- aA page zoom is not driven in the Simulator (no UI automation); source, WKWebView pageZoom and the phone cover it.
- Simulator cold start on the runner is slow (Safari openurl timed out at 60 s once); warm-up and retries are in, watch
  `skipped` in `gaps.md` on later runs.
- A push of this branch can start `webkit-sim` (paths from main); cancel it with `gh run cancel`.
