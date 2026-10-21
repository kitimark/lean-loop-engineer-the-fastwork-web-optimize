# sup-warmup handoff

State: branch `worktree-wf_f3ac4663-d82-2`, commit named in the report. Local-lane measurement of the four cold-start
costs for fw-sup stage 0; no code outside the note's folder changed.

Read first: `research/notes/2026/10-21-warmup-costs.md` (method, tables, grace rule), then
`research/notes/2026/warmup-costs/results.json` (every sample, with load and free memory) and `measure.mjs` (the
harness; one kind per call, merges into results.json).

Verified:
- `node research/notes/2026/warmup-costs/render.mjs --check` is ok (the note's tables equal the render of results.json).
- Samples: lake serve 5, fwcore 5 + 5 (time -l), fwcore starts in a vitest worker 3 x 12, Simulator 3 fresh devices
  (first boot, reboot, 2 shutdowns, delete), lake build from 1,183 local spans. Each sample has load1, free MB, avail MB.
- Simulator: only devices named `fw-warmup-<pid>-<n>` were created; all deleted (`leftoverDevices` in results.json);
  `scripts/sim-lock.sh` held for the series and released. Pre-existing devices untouched.
- `fw land --dry` VERDICT line is in the report.

Open:
- Lean encoding of the grace rule (K = 10, gMin 60 s, gMax 1800 s) is sup-model / sup-route; K is INFERRED and should
  be fitted to reuse gaps once sup-baseline logs exist.
- No per-module lake build time exists; the p99 is of the whole `lake build` stage.
- Cold file cache not measured (needs privileged `purge`).

Conventions: never type a sample-derived number by hand: re-run `measure.mjs <kind>` and `render.mjs`. A result run
never sets `FW_WARMUP_NOWAIT` (it skips the no-land wait; debug only). Results are this Mac under load, never CI or
phone numbers.
