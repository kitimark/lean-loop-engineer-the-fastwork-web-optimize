# Handoff: sim-speed

State: branch `ci/sim-speed` (worktree branch pushed as `ci/sim-speed`), probe and note committed. Read first:
`research/notes/2026/10-17-sim-speed.md` (answer, table, risks, ranked recommendation).

Files
- `.github/workflows/sim-speed.yml`: boot + connect + one page, per-phase marks, host sampler. Arms: base pre fast quiet
  bg f6 early qe combo xl; inputs `arms` (default `base f6 combo xl`) and `reps` (1..3). Runs on push to `ci/sim-speed`.
- `.github/scripts/sim-speed-probe.mjs`, `sim-speed-mark.sh`, `sim-speed-sampler.sh`. The probe imports
  `packages/measure-webkit/src` read-only; it never edits it or `webkit-sim.yml`.

Runs: R1 39038015877, R2 39041142432, R3 39043591653; baseline 39036078841. Download:
`gh run download <id> -n sim-speed-<arm>-<rep>`; marks.txt is `<epoch ms> <label>`, sampler.txt has load/memory/top.

Findings: lane is host-capacity bound; xlarge runner (boot 41-50 s vs median 120 s) and one boot per job (warm session
5-22 s vs 101-218 s) are the levers; overlap, quieting, bootout, image device, fast connect gave no gain.

Open items
- The fast connect (f6/combo/xl) failed in 5 of 9 R3 jobs (`no tab (0 tabs)` / `fetch failed`, proxy output empty);
  not root-caused. Check proxy restart after 3 openurls in `sim-speed-probe.mjs` before trusting it.
- Direct Web Inspector / safaridriver connection was not tested.
- The ci-webkit owner applies the recommendations (webkit-sim.yml, packages/measure-webkit); verify class stability over
  >= 3 CI jobs afterwards (xlarge, warm reuse).
- Every `ci/**` push runs all workflows; cancel the others when only this one is wanted.

Conventions: measured on CI only; local runs only under sim-lock; no personal data; attribution lines on commits.
