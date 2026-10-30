# preset-gate-evidence handoff

- Branch `worktree-wf_da121197-358-1`, worktree `.claude/worktrees/wf_da121197-358-1`. Last commit: see `git log -1` on the
  branch. No CI push; no CI runs started.
- State: `lean/Fw/Preset/GateEvidence.lean` holds the gate-run table (`runs`), admissions, pinned waivers and the member
  rule `status`; `Fw.Preset.Gen.run` throws on `problems`, prints one `gate evidence:` line per member and writes
  `packages/contracts/golden/preset/gate-evidence.jsonl`.
- Verified: `lake build`, the module's `#guard`s, Gen.run regenerated with only the new golden changing, ci-paths test 56
  pass, runner land-inputs 73 pass, @fw/contracts test 11 pass, check.sh green (slot). Dry land: see the report.
- Result: v2-proved `engine.scroll:unthrottle` proved by run 40101370753; the other five (preset, member) pairs are
  pending with reasons naming 41087718575, 41078004214 or 40287895072 and the user step threaded-look.
- Open (follow-ups): feed `runs` from the gate merge output instead of Lean data; a run of the three-flag set would
  decide faded-pause; the user's threaded-look decision changes the admissions and waivers (edit both, plus
  `waivers_pinned`).
- Conventions: admission set = the preset's exact flag set at the commit that first wrote the member into the preset
  golden (`git show <sha>:packages/contracts/golden/preset/<preset>.json`); the newest run of exactly that set decides
  per engine.
- Read first: `research/notes/2026/10-31-preset-gate-evidence.md`, then `lean/Fw/Preset/GateEvidence.lean`.
