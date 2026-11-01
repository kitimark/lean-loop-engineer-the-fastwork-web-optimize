# dry-land-deps: the Lean rule for which dry-land check waits for which

Split 1 of dry-land-waves (its final design round was refused: the TS `checkKind` on dfa8a1815,
apps/runner/src/land.ts:221-227, classified `["sh", "lean/scripts/check.sh"]` as `other`). This task holds the Lean
module and its goldens only. The TS wiring is the next task, dry-land-wiring.

## What the rule says

- CONFIRMED (lean/Fw/Ops/LandDry.lean:96-105, `Kind`): a check is one of install, lakeLint, fwcoreBuild, coreUser,
  other, by its command line. `fwcoreBuild` holds two command lines: `sh scripts/fwcore-build.sh` (`BUILD_ARGV`,
  apps/runner/src/land-remote.ts:409) and `sh lean/scripts/check.sh`, which runs `sh ../scripts/fwcore-build.sh` at
  lean/scripts/check.sh:37. scripts/fwcore-build.sh:42 runs `lake build` in `lean/`, and its binary is
  `lean/.lake/build/bin/fwcore` (scripts/fwcore-build.sh:29).
- CONFIRMED (LandDry.lean:110-113, `Kind.buildsLake`): lakeLint and fwcoreBuild build the lake.
- CONFIRMED (LandDry.lean:117-134, `kindDep`, `edge`, `deps`): every check waits for the install; fwcoreBuild waits for
  lakeLint; coreUser waits for fwcoreBuild and lakeLint; two checks of the same lake-building kind wait by index.
- CONFIRMED (LandDry.lean:80-84, `waves`): one wave holds reads, lints and local; `deps` orders the checks inside it.

## Theorems

| theorem | line | statement |
|---|---|---|
| `lake_serial` | LandDry.lean:144 | two different lake-building checks are ordered: one waits for the other |
| `core_after_builds` | LandDry.lean:159 | every coreUser waits for every lakeLint and fwcoreBuild of the list |
| `install_first` | LandDry.lean:174 | every check other than an install waits for every install |
| `kindDep_rank` | LandDry.lean:195 | a kind waits only for a kind of lower rank (no cycle) |
| `par_eq_seq` | LandDry.lean:47 | the one-wave verdict equals the old sequential verdict |

Golden: packages/contracts/golden/ops/land-dry-deps.jsonl (13 kind lists) and land-dry.jsonl (8 phase rows), generated
from Lean and guarded by the `#guard`s in lean/Fw/Ops/LandDryGolden.lean:4-6. The last deps row is the plan that holds
check.sh and the fwcore build script as two fwcoreBuild checks: `[install, lakeLint, fwcoreBuild, fwcoreBuild,
coreUser, other]` gives deps `[[], [0], [0,1], [0,1,2], [0,1,2,3], [0]]` (also a `#guard` at LandDry.lean:209-210).

## Threat model

Must catch:
- two `lake build` runs in one `lean/.lake`. Lake takes no lock on the build directory (CONFIRMED,
  Lake/Util/Lock.lean:17-20@eb6cafb), and `LAKE_SLOT_POOLS='full 4'` (lean/Fw/Sched/LakeSlot.lean:276) gives two slots
  (`_ls_take`, scripts/lake-slot-lib.sh:38-49), so the slots let two builds run at once. `lake_serial` orders them.
- a `fwcore` user running while a lake build can still relink `lean/.lake/build/bin/fwcore`: `core_after_builds`.

Need not catch: builds in other worktrees (each has its own `lean/.lake`); a command line the classifier maps to the
wrong kind. Classification by command line lives in TS until dry-land-wiring checks it against Lean.

## Accepted limits

Lean and golden only; no TS wiring (task dry-land-wiring); no measurement. The rule stays consumed by a TS stand-in
until a fwcore op replaces it.
