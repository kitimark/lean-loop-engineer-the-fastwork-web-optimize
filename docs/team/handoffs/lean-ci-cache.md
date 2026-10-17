# lean-ci-cache handoff (CI lean.yml fails on every run with a restored Lake cache)

State: committed on this worktree branch (see `git log -1`); lead lands on main.

## Cause (CONFIRMED, Lake source @eb6cafb = toolchain v4.35.0)
- With `enableArtifactCache`, a module served from the cache is restored by `restoreNeededArtifacts` (only the
  `.ilean`, `Lake/Build/Module.lean:816-819`) unless the package's `restoreAllArtifacts` is true
  (`:1058-1061`, `:1069`; default false via `Lake/Config/Monad.lean:182-183`, docs `Lake/Config/PackageConfig.lean:291-301`).
- Lake itself compiles importers against the cached paths, so `lake build`/`lake test` pass, but `.lake/build/lib/lean`
  holds no `.olean`. `lake exe mathview` imports via `initSearchPath` on that dir (`lean/MathViewMain.lean:37-39`), so it fails.

## Fix
- `lean/lakefile.toml`: `restoreAllArtifacts = true`. Restore = hard link (`Lake/Build/Common.lean:648-654`), so the
  cache speedup stays. No script or workflow change needed; check-fast.sh unchanged.

## Reproduction (MEASURED, macOS arm64, shared scratch `LAKE_CACHE_DIR`, fresh copies of lean/ without `.lake`)
| Copy | Lakefile | Result | Wall |
|---|---|---|---|
| A (cold cache, like CI run 1) | old | check.sh green | 117 s (incl. cold build) |
| B (filled cache, empty .lake) | old | check.sh FAIL: `Fw.olean ... does not exist` (mathview) | 7 s |
| C (filled cache, empty .lake) | new | check.sh green, 0 rebuilds (82 jobs replayed) | 52 s (mathview lint miss) |
- Fresh-tree `lake build` from cache: old 0.20/0.32 s, 0 oleans; new 0.20/0.22 s, 42 oleans (link count 3).
- check-fast.sh in C: ok 2.5 s (build 0.2 s, lint 0.1 s cache hit).
- Note: `lake test` reads `../packages/contracts/golden`, so a repro copy needs that sibling dir.

## Open items
- Not yet confirmed on GitHub CI (needs a `ci/*` push by the lead). The cache key includes lakefile.toml, so the first
  run after landing saves a new entry via the restore-keys fallback; the second run is the real test.
- `lean/README.md` cache paragraph could mention `restoreAllArtifacts` (not in my file list).
