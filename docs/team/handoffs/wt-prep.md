# wt-prep handoff (E1, E3)

State: branch worktree-agent-a9fcc32afdf05606e, one commit (scripts + tool + this note).

Files
- scripts/wt-prep.sh: clones main lean/.lake with `cp -c -R` into `.lake.partial`, then mv (no torn target).
  Skips with a message while a lake/lean process has its cwd under main lean/ (Lake has no build lock file:
  lean4@eb6cafb src/lake/Lake/Util/Lock.lean:18; so pgrep + one batched lsof). Prints one line with seconds.
- scripts/sim-lock.sh: `acquire <owner> [--wait N] | release | status`; mkdir lock at
  <main>/.local/locks/sim with owner+pid files; stale recovery when pid is dead. SHELL STAND-IN for Fw.Lease.
  pid recorded is the caller's $PPID, so call it from the long-lived shell, not a throwaway subshell.
- docs/team/tools/load-sample.sh [interval] [duration]: JSONL to <main>/.local/load/<date>.jsonl with idle,
  memFree, swapMB, cpuProbeMs (20000-iteration loop) and {n,cpu} for lean, node, docker, sim, claude. No load1.
- scripts/test-wt-prep.sh: scratch worktree, wt-prep, timed lake build x2, removes worktree + branch.

Measured (MEASURED): clone 0-1 s; first lake build after clone 4.05 s (not a pure no-op: Fw.Wire, Fw, Main,
Golden and Fw.Wire:c.o relinked/recompiled, likely path-dependent traces), second build 0.19 s.
node_modules: `pnpm install --offline --frozen-lockfile` 7.8 s vs `cp -c -R` 13.0 s (and cp misses
apps/*/node_modules); keep pnpm, so wt-prep does not touch node_modules.

Open
- Q4 clean-build mkdir lock is not in wt-prep (it never builds); add in the build wrapper / fw job.
- sim-lock.sh and load-sample.sh were only smoke-tested lightly (sim-lock not exercised by test script).
- Why the 4 s relink: unexplored; a trace path-normalisation fix could make it a true no-op.
Read first: scripts/wt-prep.sh.
