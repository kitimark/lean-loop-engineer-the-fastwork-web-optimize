# xctrace on a GitHub macOS runner: which hitch and frame signals can CI record?

Question: can a free GitHub macOS runner give us a render-hitch or frame-timing signal for the WebKit Simulator lane, with
three methods: Animation Hitches on the Simulator, WebKit kdebug/os_signposts, XCTHitchMetric. Tags: MEASURED (a CI run id
named here), CONFIRMED (Apple doc or WebKit source cited), INFERRED (reasoned, not seen).

## Answer

| method | works on a GitHub macOS runner? | A/A (vm 1 vs vm 2) |
|---|---|---|
| Animation Hitches, Simulator target | NO | same error on both VMs |
| WebKit kdebug / os_signposts, Simulator target | NO | not recordable on vm 1 |
| os_signposts, host recording of the Simulator | PARTLY: one VM of two finalizes a trace; it holds no WebKit signposts | vm 2 yes, vm 1 no (no spread to give) |
| XCTHitchMetric | NO: the tests pass, no hitch value is reported | zero values on both |
| Animation Hitches / System Trace, host recording | NO: trace never finalizes into tables | vm 2 fails, vm 1 no data |

Nothing here yields a render-hitch number, so no reducer, workflow or lane is kept. The harness is deleted in the
commit after e1a1f84d; the code it ran is at commits fc46ae97 and e1a1f84d on this branch, and the numbers below are
the record.

The runner is a virtual machine with no display and no real GPU (MEASURED, run 39683465909 facts step: model "Apple M1
(Virtual)", `kern.hv_vmm_present=1`, 3 CPUs, 7.5 GB, `system_profiler SPDisplaysDataType` printed nothing). Even where a
render-hitch table would exist, the frames would not be presented by a real GPU and so would say little about a phone.
Stated as a limit: INFERRED, not tested against a GPU-backed Mac, which is the follow-up below.

## Environment (MEASURED, run 39683465909)

macOS 27.0.1 (26A434), Xcode 27.0 (27A266a), xctrace 27.0, image `macos27` 20261012.0260.1, iOS 27.0 (24A434) Simulator
`fw-iphone-27`. Passwordless `sudo -n` works, SIP is disabled, Developer mode is on.

## Runs (6 of 6 used)

| run | what it tried |
|---|---|
| 39648103794 | first run of the first harness; no finding from it is used here |
| 39653044145 | Simulator recordings of all three templates, two VMs |
| 39664131424 | XCTHitchMetric in autoStop mode; arms did not start on vm 1 |
| 39674462007 | XCTHitchMetric alone, manual start/stop |
| 39683465909 | all stages plus `XCTClockMetric` as a control |
| 39693161181 | host recordings only, time-limit stop, 360 s stop wait, traces kept |

## Method 1: Animation Hitches on the Simulator: NO

- Run 39653044145, both VMs: `xctrace record --template "Animation Hitches" --device <sim> --all-processes` starts, then
  prints `[Error] Hitches is not supported on this platform.`; export then fails with "Trace is malformed - run data is
  missing." Exit codes differ (vm 1: 2, vm 2: 0), the message is the same. MEASURED.
- Run 39683465909 vm 1: `No devices found matching: <udid>`. The Simulator device was lost after the XCTHitchMetric stage
  wedged simctl, so this arm is a harness ordering artifact and counts for nothing either way. Run 39664131424: no start
  line. MEASURED.
- Apple documents the metric as a commit hitch / render hitch split with a hitch rate in ms/s (good up to 10, warning up to
  25, critical up to 50) and says the Hitches instrument is not available for visionOS (CONFIRMED, "Understanding hitches in
  your app", Apple developer documentation, `xcode/understanding-hitches-in-your-app`). Nothing in it promises the template on a
  Simulator device; the error above says it does not run there. INFERRED: the Simulator has no render-server frame
  pipeline the instrument can read.

## Method 2: WebKit kdebug / os_signposts

Simulator target: NO.
- Run 39683465909 vm 1, the only Simulator stage that completed: the os_signpost recording ended after 1.03 s with
  "Error encountered". xctrace: `Unexpected failure: Data source agent failed to setup` and `Kernel trace recording is
  unavailable on fw-iphone-27 (27.0)`; exit 2. The exported rows are `com.apple.UIKit UpdateCycle`,
  `com.apple.coreanimation CAImageQueue`, `Transaction` and a few system subsystems; 0 WebKit subsystem rows, 0 rows
  inside the zone A or B windows. System Trace ended after 0.754 s the same way; exporting kdebug, os-signpost,
  thread-state, context-switch and time-profile from that trace gave 0 rows each. MEASURED.
- Run 39653044145: System Trace ended in SIGSEGV (vm 1) and SIGKILL (vm 2); signposts exited early even with sudo. MEASURED.

Host recording (the Simulator runs as host processes, so `xctrace` on the host sees them):
- Run 39693161181 vm 2 finalized: 17.87 s, "User pressed Stop" after a 360 s stop wait. Tables: os-signpost 3,169 rows,
  OSSignpostIntervals 739, kdebug 92,914, kdebug-strings 88,071. Zone A (the first scroll window): 968 signpost rows,
  243 intervals totalling 1,740.65 ms, 10,185 kdebug rows. Zone B: 540 rows, 141 intervals, 26,271 ms, 31,998 kdebug rows.
  MEASURED.
- The signposts are `SwapPresent` intervals and `frameReady` events from `SimRenderServer` and `SimFramebufferServer`:
  the Simulator's host-side frame presentation on a VM. There are 0 WebKit-subsystem signposts. The kdebug rows are class
  0x1f (DBG_DYLD) subclass 0x5 (DBG_DYLD_UUID, dyld image-map events) only (88,072) plus TRACE (4,842); 0 rows of class
  0x21 (DBG_APPS) (CONFIRMED, xnu `bsd/sys/kdebug.h`: DBG_DYLD 31, DBG_APPS 33, DBG_DYLD_UUID 5); WebContent emitted 26 events, WebKit.GPU 8, MobileSafari
  4. MEASURED.
- Why no WebKit rows: WebKit's gated signposts are emitted only when
  `kdebug_is_enabled(KDBG_EVENTID(DBG_APPS, DBG_APPS_WEBKIT_MISC, 0))` holds, with `DBG_APPS_WEBKIT_MISC = 0xFF`
  (`Source/WTF/wtf/SystemTracing.h:316-326` and `:44@862f17d`). The recording held no DBG_APPS (0x21) events at all, so nothing shows the WebKit gate was on.
  CONFIRMED (source), the link to our empty result INFERRED. `slowFrame` at
  `Source/WebKit/UIProcess/RemoteLayerTree/RemoteLayerTreeDrawingAreaProxy.mm:435@862f17d` is a gated signpost, so it
  was off. The `*Always` macros (`SystemTracing.h:346-347@862f17d`) skip the gate, but the scrolling ones
  (`Source/WebKit/UIProcess/RemoteLayerTree/ios/ScrollingTreeScrollingNodeDelegateIOS.mm:111,180@862f17d`) run only when scrolling-performance testing is enabled in the
  UI process. CONFIRMED (source); not tried.
- A/A: run 39693161181 vm 1 started the same recording after 28.6 s, never exported, and the step hit its 10-minute
  limit. Runs 39683465909 vm 1 and vm 2: the 90 s SIGKILL left a malformed trace ("Document Missing Template Error").
  So only one VM of two ever gave a readable trace; no row-count spread exists. MEASURED.
- Run 39693161181 vm 1 also printed `proxy did not list the Simulator in 160 s` in one stage: no data. MEASURED.

Host System Trace (kdebug with context-switch): no. Run 39693161181 vm 2: recording ended on the time limit, SIGKILL,
toc export "Document Missing Template Error", 0 tables. vm 1: no start line without sudo, then recording with sudo after
39 s and the step hit its 10-minute limit. MEASURED.

Host Animation Hitches: no. Run 39693161181 vm 2: "Reached specified time limit", the process ended on SIGSEGV, toc export
"Document Missing Template Error", 0 tables. Run 39683465909 vm 1: sudo start after 43.6 s, toc export timed out. MEASURED.

## Method 3: XCTHitchMetric on the Simulator: NO (no value)

- Apple: "A metric to measure the number of hitches your UI encounters in a performance test", introduced iOS 26.0
  (CONFIRMED, `xctest/xcthitchmetric`, Apple developer documentation).
- Run 39674462007 vm 1: both UI tests passed (68.2 s and 89.3 s) and the xcresult summary says 2 passed, 0 statistics. The
  `PerformanceMetrics` table in `hitch.xcresult/database.sqlite3` has 0 rows; no "measured [" line in the log. MEASURED.
- Run 39664131424: the default autoStop mode raised "-stopMeasuring shouldn't be called in autoStop mode"
  (NSInternalInconsistencyException), so the test used manual start/stop. MEASURED.
- Control, run 39683465909: with `XCTClockMetric` alongside, the clock reports and the hitch metric does not.

| cell | clock average | RSD | values (s) |
|---|---|---|---|
| vm 1 zone A | 2.659 s | 3.26% | 2.573, 2.778, 2.626 |
| vm 2 zone A | 3.073 s | 12.13% | 3.600, 2.801, 2.818 |
| vm 2 zone B | 2.420 s | 52.2% | 4.206, 1.514, 1.540 |
| vm 1 zone B | no value | - | the test never finished; xcodebuild TERM at 15 min, exit 143 |

  The zone A A/A spread of the clock is 15.6% (vm 1 vs vm 2), the zone B one cannot be computed. So XCUITest swipes in
  Mobile Safari run on the VM; the hitch metric stays empty. MEASURED.
- The stage wedged both VMs: `xcresulttool` after the TERM hung (0-byte summary), and vm 2 ran 1 h 20 min until the job
  timeout cancelled it. MEASURED.
- Why empty: INFERRED to be the same cause as method 1 (hitch data is unsupported on this platform); no log line says so.

## What the task leaves unknown

- Whether a host recording with the WebKit signpost subclass (0xFF) enabled gives WebKit frame signposts: not run, because
  the os_signpost instrument offers no knob for it in the runs above. INFERRED to need a `kdebug` filter or the
  `*Always` scrolling signposts.
- Whether any of this changes on a GPU-backed Mac (the Mac Safari task). On the VM, render hitches are meaningless by
  construction.

## Follow-ups (none started)

1. Host `xctrace` with a kdebug filter that turns on class 0x21 (DBG_APPS) subclass 0xFF, then count WebKit signposts per zone.
2. Turn on scrolling-performance testing in the Simulator's UI process to get the `ScrollingPerformanceTest*` intervals.
3. Mac Safari on a real GPU (task mac-safari-measure) for Animation Hitches.
4. If a trace is recorded on CI again: use the time-limit stop with a long finalize wait on one VM, and treat a trace that does
   not finalize as no data; do not use SIGKILL after 90 s (it left malformed traces in every case here).
