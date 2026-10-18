# Handoff: lean-bin-slim

State: branch `worktree-wf_c585051c-284-1`; see `git log --oneline main..` for the commits. Not landed.

## Done and verified
- One executable `fwcore` runs `fwtest`, `sweepsgen` and `partsgolden` as subcommands. Routing is in
  `lean/Fw/Ops/FwCoreRoute.lean` (`route_old`: old command lines keep their meaning; `route_sub`).
- `lean/lakefile.toml`: the sweepsgen, partsgolden and fwtest exes are gone; `lake test` = `fwcore fwtest`.
  mathview and breakgen stay (stripping breaks mathview's interpreter; breakgen is the site-build cone).
- `scripts/fwcore-build.sh` strips fwcore (`strip -o` + `mv`, new inode) and records the stripped sha256.
- `Fw.Gate.ScopeGen` JSON constants take `Unit` (`compiler.extract_closed false`). They were costing 3.7 s at startup.
- Callers moved: `lean/scripts/check.sh`, `mutants.sh`, `scopegen.mjs`, CheckMap (`lake build` once), LakeJobsGen
  (regenerated), `ci-paths.test.mjs`, README.
- Differential: old exe vs new subcommand, byte-identical. See `research/notes/2026/10-18-lean-bin-slim.md`.
- `lean/Fw/Ops/LakeGc.lean` decides the lake-gc list and the alert. Theorems: never_lists_linked, never_lists_young,
  inside_root_only, list_monotone_in_age, list_complete, alert_iff. Op `ops.lakeGc`, golden
  `golden/ops/lakegc.jsonl`.
- `fw lake-gc` (`apps/runner/src/lake-gc.ts`, `scripts/lake-gc.mjs`) gathers lstat facts and prints the list and
  the command. It never deletes. Docs: `docs/team/tools/lake-gc.md`, `disk-cleanup.md`.
- Passing: `sh lean/scripts/check.sh` (green), `node --test scripts/lake-gc.test.mjs scripts/ci-paths.test.mjs`,
  runner tsc, lib/run vitest.

## Open
- `fw watch` alert `sys.lakeCache`: not wired. It touches the `Fw.Obs.Health` Code enum and rank proofs, Params,
  System decode, goldens, console-web and watch-collect, which overlap watch-stream and ci-own-trigger. Until then,
  use `fw lake-gc --check`.
- Startup is +80 ms (all `Fw` modules initialize). Followup: lazy constants.
- These messages still name `lake exe sweepsgen`: `BreakgenMain.lean:16` and `Fw/Gate/SweepsGen.lean:124`. They
  are kept byte-identical for the differential. Docs that still name the old exes: LandSpeed/GenRoute and old
  handoffs. The `Fw.Ops.LakeCache` #guard literal "fwtest" and `wt-prep.sh:20` are only test strings.
- `.github/workflows/*` were not edited. lean.yml still calls mathview, which is kept.

## Conventions
A closed term that is slow at module init: `set_option compiler.extract_closed false in` before its docstring, and
give the def a `(_ : Unit := ())` argument.
