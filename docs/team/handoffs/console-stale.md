# console-stale handoff

State: round 5 (final design round) on branch worktree-wf_6c45d729-0a2-1 (merged round-4 head f76d486 and main).

Read first: docs/team/tools/console-stale.md, lean/Fw/Obs/Stale.lean (end: build record section).

Done (round 5, lead decisions 1-4)
- No reflog, no mtime anywhere. The only source of a binary's commit is the build record written by
  scripts/fwcore-build.sh: `<sha of HEAD before the build> <sha256 of the built binary>`, after a successful build on a
  tree that is clean before and after (no merge/rebase in progress, HEAD unmoved). Accepted only when the sha256 of the
  binary on disk equals the recorded one; else svc.unknown with the hint to run the script.
- Lean (Stale.lean): `chooseBase binHash rec`, theorems chooseBase_accepted, chooseBase_at_iff (identity),
  chooseBase_mismatch, chooseBase_none, chooseBase_unknown_alerts; Health.lean: unidentified_core_alerts. Inputs are
  path prefixes: `covers`, covers_self, covers_child; touched/touched_of_mem and the three Stack theorems restated with
  a covered file. Round-4 math nits fixed (svcUnknown_iff, unknown_service_alerts).
- lean/scripts/check.sh builds through scripts/fwcore-build.sh (fw land runs it in its land worktree only: the lead runs the script in the main checkout after each land); LandSpeed checkShReads + golden
  land-speed.jsonl + runner CHECK_SH_READS gained `scripts/fwcore-build.sh`.
- console-api main.ts: codeRoot = resolve(here, ../../..) for codeCommit and buildBase; a binary that is not
  <codeRoot>/lean/.lake/build/bin/fwcore without a matching record is unknown (reason says so).
- TS stand-in build-base.ts (pure file reads, no git) and watch-svc.ts coreBase; tests updated. Tool note states the
  watcher's own code is not judged (stated limit).

Open
- Lands need `--allow lean/Fw/Wire/Obs.lean` and `--allow scripts/fwcore-build.sh` (declared writes miss them);
  also touched: lean/Fw/Console/LandSpeed.lean, lean/Fw/Obs/Health.lean, lean/scripts/check.sh, apps/runner/src/land.ts,
  packages/contracts/golden/console/land-speed.jsonl (see the dry-run list).
- The running console-api must be restarted once to write `coreCommit`; until then `svc.unknown console-api`.
- Until the main checkout's fwcore is rebuilt with `sh scripts/fwcore-build.sh`, the old core ignores `svcs`: no svc.* alert at all (restarting the watcher does not help).
- TS stand-in chooseBase to be replaced by an fwcore op.
- The watcher's own code (fw watch) is not a judged service (stated limit).
