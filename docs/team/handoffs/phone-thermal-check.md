# phone-thermal-check handoff (build, round 2)
Branch worktree-wf_3b4e5a02-d28-1; worktree .claude/worktrees/wf_3b4e5a02-d28-1; last commit: see `git log -1`. CI runs: none (Lean gates local through fw slot).
Round 2 fixes (review r1 findings): Lean `resetPlan n` and `wallMin n` (goldens for n = 16 and 4, wallmin cases; TS tests use c.n), Thermal.lean docstrings (pass = visit), note wording (stall cause not separated, stop rule, 300 s since last non-Nominal, raw/ path, MiB unit, file:line citations, Thermal State instrument via `xctrace list instruments`), generator label MB -> MiB.
Verified: see the final commit message and the report; phone session itself is done (no new session).
Open: follow-up 6 (gate between lanes) belongs to phone-thermal-pin (r476). Playwright WebKit CI check if strip stalls again.
Conventions: no device ids in output; phone proxy ports 9460/9461; raw data `.local/phone/2026-10-25-thermal/` local only.
Read first: research/notes/2026/10-25-phone-thermal-check.md; docs/team/tools/device-lag-recorder.md "Arms session guards".
TS stand-ins (no Lean): wip.mjs targetStep, parsers (parseThermalXml, parsePs, specOf, portsOf, usbEvidence), runBlock orchestration.
