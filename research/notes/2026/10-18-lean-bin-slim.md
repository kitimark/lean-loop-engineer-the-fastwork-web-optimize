---
id: 2026-10-18-lean-bin-slim
kind: note
title: "lean-bin-slim: one stripped fwcore in place of four executables, and a Lean-decided lake-gc"
status: draft
created: 2026-10-18
topics: [lean, lake, disk, artifact-cache, build]
---

Question: how many bytes do the Lean executables cost per checkout and per rebuild, and how much does merging
`fwtest`, `sweepsgen` and `partsgolden` into a stripped `fwcore` save, with every output unchanged?

Status tags: MEASURED (this Mac, `stat` byte sizes, toolchain v4.35.0, one worktree), CONFIRMED (source cited),
INFERRED. These are file sizes and outputs, not engine counts, so the CI-only rule for measurements does not apply.

## Answer

| | before | after | change |
|---|---|---|---|
| executables per checkout | 6 | 3 (fwcore, mathview, breakgen) | |
| `lean/.lake/build/bin` per checkout | 693,476,560 B | 357,955,216 B | -48 % |
| cache bytes stored by one full rebuild | 707,187,841 B | 399,550,049 B | -43 % |
| of which executables | 695,883,520 B | 388,245,728 B | -44 % |
| `fwcore --ops` startup (median of 30) | 48 ms | 129-131 ms | +80 ms |

MEASURED. The rebuild row appends a fresh def to three modules whose cones cover every executable
(`Fw/Measure/Tolerance.lean`, `Fw/Site/Breakpoints.lean`, `MathView.lean`), runs `lake build`, and sums the new
files under `.lake/build` with a link count of at least 2 (hard links into the cache). The after run took 97 s.

Sizes after: fwcore 108,989,232 B as linked by Lake (the cache keeps this one), 78,698,720 B stripped in the
checkout; mathview 177,663,296 B; breakgen 101,593,200 B. `scripts/fwcore-build.sh` strips with
`strip -o <tmp> && mv -f`, a new inode, so the cache entry is not changed and is listed by `lake-gc` once no
checkout links it.

## Differential (old executable vs new subcommand, same tree)

All byte-identical, with equal exit codes, MEASURED:
- `breakgen`: 4 command lines.
- `sweepsgen` and `fwcore sweepsgen`: 5 command lines.
- `partsgolden` and `fwcore partsgolden`: 13 output files.
- `fwtest` and `fwcore fwtest`: identical after normalizing timings; both print `fwtest: all passed`.
- `lake test` gives the same output as `fwcore fwtest`.
- `fwcore` wire replay (JSON lines) and `fwcore --ops`.

The mathview executable did not change.

## Limits

- **mathview stays a separate, unstripped executable.** It runs the Lean interpreter (`supportInterpreter`), which
  looks up compiled code by exported symbol. A stripped `fwcore mathview` failed with "native implementation not
  found" for `String.hash`. MEASURED. Merging it unstripped would add its 177.7 MB to every fwcore relink.
- **breakgen stays.** The site build runs `breakgen --check` on a narrow import cone
  (`Fw.Site.BreakpointGen` only), which is part of the site-build cache key.
- **Startup is 80 ms slower**, because `fwcore` now imports all of `Fw` through `FwTestMain`, and every module
  initializes its closed terms at load. `Fw.Gate.ScopeGen` alone cost 3.7 s until its three JSON constants became
  functions of `Unit` with `compiler.extract_closed false`. INFERRED from a `sample` profile; making the remaining
  constants lazy is a followup.

## lake-gc

On 2026-10-18 with 27 worktrees, the cache held 30.0 GB in 2,990 entries:
- 9.08 GB hard-linked by checkouts;
- 12.82 GB unlinked and younger than 2 h;
- 8.10 GB listable, 457 files.

MEASURED. `Fw.Ops.LakeGc` decides the list. The theorems `never_lists_linked`, `never_lists_young`,
`inside_root_only`, `list_monotone_in_age`, `list_complete` and `alert_iff` cover it, and the alert budget
(20 GB) is derived in the docstring of `budgetBytes`. A full `fw lake-gc --check` run took 0.33 s. Usage is in
docs/team/tools/lake-gc.md.
