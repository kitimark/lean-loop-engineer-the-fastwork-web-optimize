# phone-thermal-check handoff (build)
Branch worktree-wf_3b4e5a02-d28-1; worktree .claude/worktrees/wf_3b4e5a02-d28-1; last commit: see `git log -1` (wip.mjs fix 8ad8d7590 plus later docs commits).
CI runs: none yet (phone run is local; one ci/phone-thermal-check push for the Lean check is optional).
Verified: measure-webkit tests 793 pass (device-faults 18, device-thermal 8, device-phone-run 11, device-phone-env 8, wip-target-swap 7); Lean builds PhoneArms and Thermal.
Phone run DONE: strip measured (counts and frames same, layers 110->38 at y 0, no stall); every visit ended Serious, battery stayed 33 C. Raw: `.local/phone/2026-10-25-thermal/` (local only). Note: research/notes/2026/10-25-phone-thermal-check.md.
Open: final checks (check.sh, tests, runner land-inputs, merge main, plan lint, dry land, review ready).

What changed
- Lean: `lean/Fw/Device/PhoneArms.lean` (hand reset, fault-drop refusal, usbReset classify/wait, ForeignProxy verdicts) and `lean/Fw/Device/Thermal.lean` (gate, preflight, passesRun, resume, pauseOver); goldens `packages/contracts/golden/device/{phone-arms,thermal}.jsonl` (regenerate with `lake env lean --run scripts/{PhoneArmsGolden,DeviceThermalGolden}.lean`); wired in Fw.lean, check.sh, Trigger.lean, triggers.jsonl.
- TS twins and glue (packages/measure-webkit/src): device-faults.mjs, device-thermal.mjs (xctrace reader), device-phone-env.mjs (ps/lsof/log), device-phone-run.mjs (`runBlock` with `deps`), device-cli.mjs (`--only`, `thermal`), wip.mjs (`targetStep`).
- TS stand-ins (no Lean): wip.mjs target-swap step, parsers (parseThermalXml, parsePs, specOf, portsOf, usbEvidence), runBlock orchestration.
Conventions: no device ids in any output (pipe through a redaction); phone proxy ports 9460/9461; one phone run at a time (`ps` for device-cli first); the strip re-measure is its own visit in its own session.
Read first: docs/team/tools/device-lag-recorder.md section "Arms session guards"; research/notes/2026/10-25-phone-thermal-check.md when it exists.
