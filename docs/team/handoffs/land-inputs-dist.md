# land-inputs-dist handoff

State: apps/runner/test/land-inputs.test.ts green (55/55) with and without a local apps/site/dist/aot; `pnpm test` in apps/runner 1618 passed.

Decision: explicit named exclusion, not a declared read.
- Cause: the static scan (`escapes`) resolves `../` strings and keeps a path only if `existsSync`; dist/aot exists only after a local site build, so the result depended on the machine.
- Why not declare: dist/aot is gitignored build output. The land key hashes tracked files, so a read of it never moves the key; the
  "every PACKAGE_EXTRA_READS entry is exercised" test requires a tracked match or a deliberate directory, so it would refuse it.
  Its inputs are tracked apps/site sources, which a change selects already.
- Change: `BUILD_OUTPUT_READS` (one path, with reason) in the test; the per-package reads test filters on that exact key. No pattern.
- Not changed: apps/runner/src/land.ts (no edit needed).

Open: if another gitignored output is read by a package, add its exact path with a reason to BUILD_OUTPUT_READS.
Writes: only the test and this file.
