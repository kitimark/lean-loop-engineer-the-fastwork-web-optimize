# xctrace-ci-probe handoff

State: branch worktree-wf_3d7f87b0-856-1; note done, harness removed (see `git log` for the removal commit). All 6 CI runs used.
Read first: research/notes/2026/10-2x-xctrace-ci.md (answer table at the top).

Answer per method on a free GitHub macOS runner (a VM, no display, no real GPU):
- Animation Hitches on the Simulator: NO (`Hitches is not supported on this platform`, run 39653044145, both VMs).
- WebKit kdebug/os_signposts on the Simulator device: NO (`Kernel trace recording is unavailable`, run 39683465909 vm 1).
- os_signposts recorded on the host: vm 2 finalizes (run 39693161181), vm 1 does not; the rows are SimRenderServer
  SwapPresent/frameReady, 0 WebKit-subsystem signposts. No A/A spread exists.
- XCTHitchMetric: NO value (tests pass, PerformanceMetrics has 0 rows, run 39674462007); XCTClockMetric works (zone A A/A 15.6%).

Kept: only the note and this handoff. Not kept: the workflow, the xctrace code, its tests and the reducer (no Lean goldens,
no lane). The code is in commits fc46ae97 and e1a1f84d if someone wants it back; restoring the workflow also needs the
trigger row in Lean (Fw/Ci/Trigger) and regenerated goldens.

Open / follow-ups (none started):
1. Host xctrace with a kdebug filter for class 0x1f subclass 0xFF (WebKit signposts gate, SystemTracing.h:316-326@862f17d).
2. Scrolling-performance testing on in the Simulator UI process (ScrollingPerformanceTest* Always signposts).
3. Real-GPU Mac Safari (task mac-safari-measure) for Animation Hitches.

Conventions learned: on these VMs never SIGKILL a recording after 90 s (malformed trace every time); XCTHitchMetric stages
wedge simctl, so run them last and gate every stage on not-cancelled; xcresulttool hangs after a TERM.
