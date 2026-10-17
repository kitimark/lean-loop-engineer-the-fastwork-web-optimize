# Handoff: sim-speed

State: probe and note on `main` (merge 7563f79); review c13e9e8 (changes requested) answered by the sim-speed-fix
commit on this worktree branch (note revision 2, iwdp pin). Read first: `research/notes/2026/10-17-sim-speed.md`
(answer, table, baseline run, cost, risks, ranked recommendation), then `research/notes/2026/10-17-sim-speed-review.md`.

Files
- `.github/workflows/sim-speed.yml`: boot + connect + one page, per-phase marks, host sampler. Arms: base pre fast quiet
  bg f6 early qe combo xl; inputs `arms` and `reps` (1..3). Runs on push to `ci/sim-speed`.
- `.github/scripts/sim-speed-probe.mjs`, `sim-speed-mark.sh`, `sim-speed-sampler.sh` (imports
  `packages/measure-webkit/src` read-only).
- iwdp source pin: `refs/upstream/sources.lock.yaml` id `ios-webkit-debug-proxy` (v1.9.2 = 278bf48 = brew 1.9.2_2);
  fetch with `node scripts/refs-fetch.mjs ios-webkit-debug-proxy`.

Runs: R1 39038015877, R2 39041142432, R3 39043591653; baseline 39036078841. Numbers: `gh run view <id> --log`, grep
`MARK <epoch ms> <label>`; job minutes from `gh run view <id> --json jobs`; host load from artifacts (`sampler.txt`).
Boot = "boot begin" to "bootstatus -b returned".

Findings: host-capacity bound. xlarge measured (boot about 60 to 77 s faster) but REJECTED (user 2026-10-17: no paid
runners; larger runners are billed even on public repos). Ranked levers now: fail fast on dead proxy / "no page
target", keep Safari between sessions (lane already boots once), polling instead of `T()` sleeps.

Open items
- Probe bug: after `proxy restarted` every poll is `fetch failed` (R3 xl-2, xl-3, combo-1). Await the old proxy's
  exit, check `alive()`, log exit code in `sim-speed-probe.mjs:160` before reusing the fast connect.
- Keep-Safari change needs a session-2 count equality check over >= 3 CI jobs before adoption.
- Direct Web Inspector / safaridriver connection not tested. xlarge with the legacy connect never run (moot: rejected).
- Every `ci/**` push runs all workflows; cancel the others when only this one is wanted.

Conventions: measured on CI only; no new CI in the fix; no personal data; attribution lines and `Task: sim-speed`.
