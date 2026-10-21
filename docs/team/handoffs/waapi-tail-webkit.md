# waapi-tail-webkit handoff (phase 1 of 2, round 2: source, instrument, one mac WebKit run)

State: branch worktree-wf_79c0837e-67c-1, pushed as ci/waapi-tail-webkit. Round 1 d85cf355; round 2 code 6cfc27ed; run: see the last line.
No classification and no measurement claim (phase 2). Read first: research/notes/2026/10-21-waapi-tail-webkit.md.

Round 2 (each review finding):
1. Recorder rows: one MutationObserver, attributeOldValue, one row per MutationRecord in record order (nav-transition.ts `apply`).
   Test writes --morph, class, data-fw-morph in one task and expects base, cls, data. Header comment and note corrected.
2. The kit (kit.mjs `stampRead`, called first in `snap`) calls `window.__fwDebug.navTransitionRead()`: it drains the observer and
   logs a `read` row while hot. Candidate table (C1, C2, C-probe, C0) re-stated with the rows this instrument can show.
3. rAF loop only while hot: starts at the first nav row, ends at the first frame at or past hotUntil (test).
4. WebKit lines re-read at 862f17d (Styleable.cpp:570-759, 606-618, 625-633, 646-651, 694-756; StyleTreeResolver.cpp:887-913).
   Where the reviewer's range differs from the source, the source line is cited (606-618 not 623, 625-633 not 640, 907-913 not 910).
5. Flip paths A (poll), M (marker finish), P (push task) as INFERRED with their rows, in the note.
6. debug.requests.json removed. The request is the push-line key `debug=nav-transition`: Lean Fw.Ci.Trigger (`probeDebugs`,
   build_ok, build_debug_none, build_debug_some, build_debug_unknown, golden triggers.jsonl), twin trajectory-line.mjs,
   workflow site output `debug` -> `FW_DEBUG` of the probe steps; debug.mjs reads only FW_DEBUG.

Mac leg: `probe-apple` ran on dispatch only. It now also runs on a push whose line has `debug=`. That `if:` is YAML (TS-level
stand-in, not Lean); the Lean lane flag changed with it (Fw.Ci.Intent macosFiles + trajectory-probe.yml, golden intent.jsonl).
Writes outside round 1's set: lean/Fw/Ci/Intent.lean, golden/ci/intent.jsonl, docs/team/tools/trajectory-probe.md,
.github/scripts/trajectory-line.test.mjs, research note.
TS stand-ins (no Lean spec, debug only): navDebugOn, installNavTransitionDebug, stampRead, debugFor, withDebug, readDebug, the
probe-apple `if:`.
Verified at 6cfc27ed: site test 5548 pass (4 skipped before this task), site typecheck, gate-breakpoints 441, runner 1677, ci-paths 52,
trajectory-line tests 4, part-footprint --check, lean/scripts/check.sh green.
Open: phase 2 classifies the rows (C1/C2/C-probe/C0/C3/C4) over >= 3 runs on separate jobs; the `read` rows decide C-probe per rep.
