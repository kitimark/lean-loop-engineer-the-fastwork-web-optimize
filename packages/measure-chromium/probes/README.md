# Probes

Diagnostic profiles (`"kind": "probe"`): runs that may crash by design and record no counts. `profiles/` holds only counts
profiles; the split is Lean's (`Fw.Measure.Profile`, `Kind.dir`) and `test/profile.test.mjs` checks it.

The counts lane reads `profiles/` only. To run a probe, copy it to `profiles/` on a `ci/*` branch, push, and dispatch
`pnpm -s fw run --engines chromium --target <t> --profile <id> --ref ci/<branch>`; the counts jobs print one `PROBE <variant>
<status>` line per variant and the classify job fails by design.

| probe | task | what it asks |
|---|---|---|
| crash-1280, crash-860, crash-861 | chromium-desktop-crash | does the counts harness crash at that width |
| crash-probe-1, crash-probe-2 | chromium-desktop-crash | which harness flag or page CSS removes the crash |
| balance-repro | chrome-balance-repro | does stock Chrome (no harness) crash on the people title alone |
