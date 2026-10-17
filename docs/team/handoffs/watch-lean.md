# watch-lean handoff
State: `obs.health` specified, proved and on the wire; `lean/scripts/check.sh` green; commit on branch
`worktree-wf_33b3c584-8ee-1` (see `git log -1 -- lean/Fw/Obs`). Read first: the module docstring of `lean/Fw/Obs/Health.lean`.

Files
- `lean/Fw/Obs/Health.lean`: types, `state`, `agentAlerts`, `sysAlerts`, `health`, 30+ theorems, `#guard`s (no imports).
- `lean/Fw/Wire/Obs.lean`: JSON codecs + round trips (`agentOf_agentJson`, `systemOf_systemJson`, `reqOf_reqJson`,
  `opHealth_reqJson`), op `obs.health`; hooked into `Fw/Wire.lean` (`ops` and `handleCore`). Build: 46 s check.sh.
- `lean/Fw/Obs/Golden.lean` (41 cases, coverage `#guard gaps == []`), `lean/scripts/ObsGolden.lean` (writer),
  `packages/contracts/golden/obs/health.jsonl`; `lake test` (`FwTestMain.lean`) diffs it.
- Regenerate: `cd lean && lake env lean --run scripts/ObsGolden.lean` (`--check` to verify only).

Conventions and contract choices (tell the CLI author)
- Thresholds in minutes (`msPerMin = 60000`), ages are truncated `now - t` in ms; edges are `≥` (exactly 20 min stalls).
- Extra param `worktreesMax` (default 20) for `worktrees.many` (`worktrees > worktreesMax`).
- Monotonicity is "loosening never adds an alert" (`Looser p q`: every upper threshold raised, `diskMinGB` lowered);
  raising `diskMinGB` adds `sys.diskLow`, so that one threshold is reversed by design.
- Numbers must be non-negative integers: the CLI floors `diskFreeGB`. Ignored: `load1`, `consolePids`, `type`, `model`,
  `tools`, `errors`, `tokens`, `inflight.verb`.
- `sim.lockOrphan`: holder string matches no live agent's id, name or task. `sim.lockLong`: held ≥ `simLockMaxMin`.
- `team.overCap`: live agents with `depth ≥ 1` (lead is depth 0) exceed `agentCap`.
- `ci.failed`: latest-started run per (workflow, branch) concluded failure / timed_out / startup_failure.
- `docker.orphan`: no live agent started at or before the container.
- `agent.ctxHigh` (> ctxResumeMax) and `agent.ctxWarn` (> ctxWarn) are independent; both may fire.
- Alerts are sorted by (code, subject, detail) and deduplicated; details hold measured values only.

Open items
- `Fw.Wire.Obs` builds in about 30 s (TreeMap `rfl` in `agentOf_agentJson`, `maxHeartbeats 4000000`).
- `Fw.lean` does not import `Fw.Obs.*` (the lib glob builds them); `check-partial.sh` does not list `Fw/Wire/Obs.lean`.
- The CLI (`watch-cli`) and the web view (`watch-web`) still need to consume `obs.health`.
