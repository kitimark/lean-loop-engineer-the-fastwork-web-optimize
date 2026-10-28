# geom-track-style handoff (graph r551)

State: branch worktree-wf_ee9ffcfe-af8-1 (worktree .claude/worktrees/wf_ee9ffcfe-af8-1). Push 1 of 3 sent: ci/geom-track-style at 7a177f5f4 (lanes breakpoint-gate + wktr, `[accel]` token asks the WKTR accel arm).
Task: which morph.geom WAAPI tracks (geom:on scrubbed, geom-timed) run on the compositor, per engine, and why. Investigation only, no site edits.

Done (committed):
- Lean: lean/Fw/Parts/MorphTrackAccel{,Gen}.lean, golden packages/contracts/golden/parts/morph-track-accel.jsonl, TS cross-check apps/site/src/parts/morph.geom/track-accel.golden.test.ts.
- Probe page script (shared): packages/gate-breakpoints/src/track-accel-page.mjs (wraps Element.animate on [data-mg], arms all / no-<prop> / none / idle / all-again).
- Chromium: packages/gate-breakpoints/src/track-accel.mjs, `node src/cli.mjs accel --out out/accel` -> accel-chromium.json; CI job `track-accel` (3 reps r1..r3) in breakpoint-gate.yml.
- WebKit: packages/measure-wktr/src/accel-{cli,page}.mjs (`[accel]` arm of wktr.yml, 3 jobs) -> accel-<mode>-<pass>.json.
- Wiring: Trigger.lean rows + cacheWriters, Overflow widths 15, triggers.jsonl, overflow.jsonl, land.ts reads.

Verified locally (not a result): Chromium probe at 1440x900 reproduces the Lean prediction (scrubbed: nothing on cc; timed: only filter tracks fail, filter-moves-pixels). ci-paths tests pass.

Open: CI data of push 1 (artifacts track-accel-r1..r3, wktr-j1..j3); WebKit arm never ran yet (first run is its debug); note research/notes/2026/10-2x-geom-track-style.md, ledger note, final checks (check.sh via fw slot, package tests, dry land, fw review ready).
Insight so far: style recalc COUNT does not discriminate (site's own animations give ~1/frame in idle); use elementCount, ms and per-frame slices.
Read first: this file, packages/gate-breakpoints/src/track-accel.mjs header, lean/Fw/Parts/MorphTrackAccel.lean.
Conventions: scratch in the session scratchpad; compound shell commands are refused, use Edit/Write; commit trailers per CLAUDE.md.
