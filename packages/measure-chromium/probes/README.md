# Probes

Diagnostic profiles (`"kind": "probe"`): runs that may crash by design and record no counts. `profiles/` holds only counts
profiles; the split is Lean's (`Fw.Measure.Profile`, `Kind.dir`) and `test/profile.test.mjs` checks it.

The lane reads a probe from `probes/` and a counts profile from `profiles/`; a name sits in exactly one of them and declares the
kind of its directory (`host.mjs`, `crash-probe.mjs`, the plan job of `chromium-counts.yml`; Lean `readOk`). `run.mjs` refuses a
kind probe in counts mode (Lean `runnable`). Dispatch a probe in the container with `pnpm -s fw run --engines chromium --target <t>
--profile <id> --ref ci/<branch>`: the counts jobs print one `PROBE <variant> <status>` line per variant and the classify job fails
by design. `.github/workflows/chrome-crash-probe.yml` runs a probe natively on linux x86_64, macOS and Windows runners.

| probe | task | what it asks |
|---|---|---|
| crash-1280, crash-860, crash-861 | chromium-desktop-crash | does the counts harness crash at that width |
| crash-probe-1, crash-probe-2 | chromium-desktop-crash | which harness flag or page CSS removes the crash |
| balance-repro | chrome-balance-repro | does stock Chrome (no harness) crash on the people title alone |
| balance-platforms | chrome-crash-platforms | the balance repro on stock Chrome for Testing on linux x86_64 (headless and headed under xvfb), macOS and Windows runners |
