# Handoff: m0-mutants

State: done on branch `worktree-wf_c2b8a932-977-4` (commit in the lead's report). Results and method:
`research/notes/2026/10-17-mutants.md`.

What exists:
- `lean/scripts/mutants.sh`, the driver. Flags:
  - `-j` workers, `-f` file, `-p` ops (`design` = the patches), `-i` survivors TSV, `-n` limit,
    `-s` str cap, `-r` run tag
  - `-b` gives the run its own baseline, so it can run beside another run
- Results go to `.cache/mutants/<tag>/{results,survivors}.tsv` (gitignored). Exit status 0 iff
  nothing survived.
- `lean/FwTest/Mutants/gen.mjs`: the mutant generator and log classifier (Node glue, no decisions).
- `lean/FwTest/Mutants/<Module>/*.patch`: 12 design mutants (v1 bug classes); line 1 says which.
- `lean/FwTest/Mutants/{Console,Serve,Meter,PathCheck,SpawnGuard,Usage,OpsWire,DeviceQueue,Wire}.lean`
  hold the killers (#guards plus 4 theorems), and `Kill.lean` imports them all.
- `lean/FwTest/Mutants/equivalent.tsv`: 3 equivalent mutants (file, id, reason), each backed by a
  guard or theorem.

Conventions:
- Mutant ids are `line:col:op:to`. They change when the module's lines move, so rerun a full pass
  after you edit an M0 module.
- Never edit `mutants.sh` while a run is going (sh reads the file as it runs): edit a copy, then `mv`.
- A full run takes about 40 min on this machine with 3 workers.

Open items:
- The lead should add `import FwTest.Mutants.Kill` to `FwTestMain.lean` (or a lakefile root), so the
  killers run in `lake build` and `lake test`.
- `check-fast.sh` lint fails on the known artifact-cache miss (`Fw.olean` not found). The gates used
  instead: lake build, lake test, and the fwcore golden diff, all green.

Read first: the note, then the `mutants.sh` header.
