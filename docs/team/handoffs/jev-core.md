# jev-core handoff

State: branch `worktree-wf_4e920a86-fa6-1`, main merged; salvaged from jev-oracle r5 (`worktree-wf_0c9d3381-3c7-1`).

Verified:
- `sh lean/scripts/check.sh` green; oracle golden 67 wire cases, 0 stale; key theorems use only propext,
  Classical.choice, Quot.sound.
- `pnpm --filter ./packages/oracle test` (7, scripted core), `apps/runner` `vitest run test/oracle.test.ts` (24, real
  fwcore through `fastCore`, about 5 s), `test/land-inputs.test.ts`, `node --test scripts/ci-paths.test.mjs`.

What landed:
- `lean/Fw/Oracle/{Core,Calibrate,Redact,Send,Questions,Body,Wire,Golden}.lean`; one question, `ci-triage`.
- Calibration fix: `certify` keeps an option's threshold only when its held-out Wilson lower bound (z = 1.645) is at
  least q (`holdOk`, `wilsonOk_sound`, `holdout_certified`). The round-5 probe (16 advised, 5 right) is a `#guard`, a
  golden and a vitest case; it certifies real only.
- `packages/oracle` (`@fw/oracle`): the key is read only after `oracle.pre` says send (tested by event order).
- `fw oracle ask|calibrate|eval` with explicit `--state`, `--replay`, `--thresholds`, `--out` files.

Open (follow-ups): a provenance check per field (dropped with the triage and mistake-class code, see jev-oracle
review rounds 3 to 5); fetching ci-triage logs (`gh run view --log-failed`); fw watch integration; replay sets
(jev-datasets) and thresholds per decision type (jev-replay); no live call was made (the lead runs it).

Conventions: Lean decides, TS does I/O; goldens regenerate with `cd lean && lake env lean --run
scripts/OracleGolden.lean`; tests never read the keychain or call the API.

Read first: `docs/team/tools/oracle.md`, `lean/Fw/Oracle.lean`, `lean/Fw/Oracle/Wire.lean` header.
