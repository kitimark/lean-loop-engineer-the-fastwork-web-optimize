# lean-fast handoff (W1-A, W1-B, E4/Q5)

State: committed on branch `worktree-agent-aa200bf10d1f0ae34`; lead lands on main.

## What changed
- `lean/lakefile.toml`: `enableArtifactCache = true` (CONFIRMED: `src/lake/Lake/Config/PackageConfig.lean:289@eb6cafb`
  option; hard links in `Lake/Build/Common.lean:489` (store) and `:652` (restore)). Cache dir is per toolchain:
  `~/.elan/toolchains/leanprover--lean4---v4.35.0/lake/cache` (504 MB after the test; Lake never prunes it).
- `lean/MathViewMain.lean`: new `--out <file>` writes the export (same bytes as stdout) in the same pass as `--lint`.
- `lean/scripts/mathview-cached.sh [--build]`: key = sha256 of Fw/**, Fw.lean, MathView*.lean, lakefile, manifest,
  lean-toolchain; stores `.lake/mathview-cache/<key>.{json,lint}` (5 newest kept); stdout = export path, stderr = lint text.
- `lean/scripts/check.sh`: only the lint line now calls the cache. `lean/scripts/check-fast.sh` (new): check-partial,
  lake build, lake test, fwcore golden diff, cached lint; per-step seconds; failure prints `check-fast: FAILED at <step>`.
- `docs/plan/tools/build-math-view.mjs`: `loadExport()` reads the cache (via `--build` on a miss); `--json` unchanged.
- `lean/README.md`: tooling table + cache paragraph.

## Measured (INFERRED: CPU idle was 5-35%, load1 70-350; sampler file was stale, used `top`)
| Step | Before | After |
|---|---|---|
| check.sh, unchanged tree (median of 3) | 32.5 s wall, 20.1 s cpu | 1.6 s wall, 0.76 s cpu |
| check-fast.sh, unchanged tree (median 3) | none | 1.0 s wall, 0.57 s cpu |
| check.sh after a Fw edit (lint miss) | 32-38 s | about 20-24 s wall, 18.8 s cpu (lint is 17 s cpu) |
| fresh tree `lake build`, no `.lake` | 80 s wall, 83 s cpu | 0.18 s wall (cache hit; populating run 25 s) |
- Export byte-identical to the old binary's stdout (cmp, 1,265,087 bytes); `build-math-view.mjs --check` green.

## Open items
- After an edit to `Fw/**` the lint re-runs in full (about 17 s cpu), so the 12 s fast target only holds on an
  unchanged tree. A per-module export would fix it (touches Fw/MathView, not mine).
- Artifact cache grows without pruning; `rm -rf` the dir above if disk is tight.
- `wt-prep.sh` still seeds `.lake` by `cp -c`; with the cache a plain `lake build` in a fresh worktree is as fast.
