# visual-diff handoff

State: branch `worktree-agent-aebbd96bb781be5c8` on top of the integration branch (`30734ae`), not merged with newer main
(its merge conflicted; the lead lands it). Tool doc: `docs/team/tools/visual-diff.md` (read first).

Done
- `lean/Fw/Gate/Pixel.lean` (import added to `lean/Fw.lean`): `verdict`, `pixel_verdict_total`, `unsettled_never_pass`,
  `tolerance_monotone`, `identical_pass`; 22 golden cases; `goldenLines` generates the golden file.
- `packages/contracts/golden/gate/pixel.jsonl`; `packages/visual-diff/test/verdict.test.mjs` checks the TS verdict against it.
- `packages/visual-diff` (pixelmatch + pngjs only here), `.github/workflows/visual-diff.yml` (plan, site, shoot matrix
  engine x shard, report). `pnpm-lock.yaml` edited for the new package (pixelmatch 8.0.0, pngjs 7.0.0).

Conventions
- Never time anything; images are artifacts only; the gate package files are imported read-only.
- Golden regeneration: a scratch `Gen.lean` printing `Fw.Gate.Pixel.goldenLines`, compiled with `lean -o` and LEAN_PATH.

TS stand-ins (not in Lean)
- Both arms absent gives cell status `nc`; probe/part/engine plumbing; the 200 ms double-screenshot settle capture.

Open items
- Mathview lint of `Fw.Gate.Pixel` was started locally (`scripts/mathview-cached.sh`) and not read back; run it on CI.
- Settled flag is a TS capture; once `Fw.Gate.Settle` lands on main, relate it to the gate's settled-sample predicate.
- WebKit (Linux Playwright port, not Mobile Safari) and overlay/mount parts were first exercised on CI.
- Per-part tolerances: none set yet (`tolerances.json`); set them from CI results, justified per part.
- CI run results: see the lead's report from this task (run id in it); download `visual-diff-report`.
