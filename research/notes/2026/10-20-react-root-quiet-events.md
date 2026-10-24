# react-root-quiet-events: the root listeners behind the WebKit EventDispatch excess

Task `react-root-quiet-events`. Answer first.

- CONFIRMED (CI runs 40122201939 and 40124553279, trajectory-probe, recorder `fw-debug=root-events`): the React root registers 14 listeners
  for the 7 animation and transition types (capture and bubble each) in every rewrite arm; all 7 types are dispatched in a
  walk of the page (WebKit on macOS 390: about 490 events, 1280: about 660; Chromium about 790 and 810). Hence
  about 2 EventDispatch and 2 FunctionCall records per event, the "batches of 2" of the Simulator pass.
- CONFIRMED by source: a root listener turns each of these events into 2 EventDispatch records (one per phase with a
  listener); with no listener, none. Events are enqueued and dispatched whether or not a listener exists.
- Variant `engine.events:quiet`: the root registers 0 of the 14 (MEASURED, same run: `registered` is `{}` in all 10 cand
  walks per engine and width), every other listener stays (Lean `quiet_keeps`, replayed against the real react-dom).
- MEASURED (section "WebKit Simulator before/after", runs 40134016822 and 40134234199, 1 VM x 2 passes): EventDispatch -53%, FunctionCall -36%;
  gate with the flag passed (run 40128098292). The earlier inference: `records_orig`
  gives 2 per event, so about 2 x 700 = 1400 of the 1500 excess; the Simulator pass has 1403 `EventDispatch>FunctionCall`
  pairs (run 39309416016).

## Mechanism

| step | what | source |
|---|---|---|
| 1 | `createRoot` and `hydrateRoot` call `listenToAllSupportedEvents(container)`; a portal calls it for its own container | `ReactDOMRoot.js:258, :357`; `ReactFiberConfigDOM.js:846` (`preparePortalMount`) @61aa00d |
| 2 | for every type in `allNativeEvents`: a bubble listener unless the type is non-delegated, and always a capture listener | `DOMPluginEventSystem.js:432-455`, `nonDelegatedEvents` :236-251 @61aa00d |
| 3 | the 7 types are in `allNativeEvents`: animationstart, animationiteration, animationend, transitionrun, transitionstart, transitioncancel, transitionend | `DOMEventProperties.js:138-148` @61aa00d |
| 4 | the registration is `target.addEventListener(type, listener, true)` or with the bubble flag, so an own `addEventListener` on the container sees it | `DOMPluginEventSystem.js:461-560`, `EventListener.js:19-37` @61aa00d |
| 5 | WebKit enqueues the CSS animation and transition events with no check for listeners | `StyleOriginatedAnimation.cpp:331-412` @862f17d |
| 6 | the pending events are dispatched at their target in the "update animations and send events" step | `AnimationTimelinesController.cpp:225-232` @862f17d |
| 7 | `fireEventListeners` calls `innerInvokeEventListeners` only when the node has listeners for the type, and that function records one `willDispatchEvent` (the EventDispatch record) per phase | `EventTarget.cpp:313-357` @862f17d (fetched from the pinned sha, not in the sparse clone) |

So with a capture and a bubble listener on `#root`, each of these events costs 2 EventDispatch records (and the page
function call inside each, the FunctionCall). `animationcancel` is not registered by React, so it costs none.

## What the page handles

CONFIRMED by `apps/site/src/parts/engine.events/quiet.scan.test.ts`, over the files `entry-client.tsx` reaches: no
`onAnimation*`/`onTransition*` prop, no component of the MUI input family (the only MUI file that sets `onAnimationStart`
is `InputBase.js`), no portal, and the hand-made listeners for these types are on their own element (`hero.exit` on the hero
element, the nav recorder on the nav). `Census.tsx` (the census page, not reached from the client entry) uses `Menu` and is
outside the scan. Limit: a later portal or input would register the types again; the test fails first.

## Lean

`lean/Fw/Parts/ReactRootOpt.lean`. `regs` is what a root registers (87 types, 142 listeners, read from react-dom 19.3.1
with a recording container), `quietRegs` drops the 7 types. One theorem per direction:

| direction | theorem |
|---|---|
| none of the 7 types is registered | `quiet_none`, `quiet_drops` |
| the original registers both phases of each | `orig_registers` |
| every other listener stays | `quiet_keeps`, `quiet_sub` |
| every type the page handles stays (premise: not in the 7, checked by the scan) | `handled_stays` |
| 14 listeners dropped | `dropped_count` |
| records per event: 2 before, 0 after, unchanged for other types | `records_orig`, `records_quiet`, `records_other` |

Golden `packages/contracts/golden/parts/react-root-quiet.jsonl` (104 lines), replayed by `quiet.scan.test.ts`: the
`registered` rows are compared with what the real `createRoot` registers on a recording container, with and without
`quietContainer`. `quiet.gen.ts` (the types and the shim) is generated from Lean and checked by the check.sh job "react-root-quiet golden check".

## Measurement (MEASURED, run 40122201939, diagnostic, 5 walks per arm; runs 40124553279 and 40126773924 (the final code, with the Lean-generated shim) repeat it with the same registrations: 14 and 0 in every walk)

Lane: `trajectory-probe` on a `ci/` push, `[trajectory fw=engine.events:quiet widths=390,1280 engines=both debug=root-events
diagnostic]` (read back from the artifact `trajectory-inputs`). The recorder (`apps/site/src/debug/root-events.ts`) counts
the watched registrations (through the prototype, so it sees what the container shim lets through) and the watched events
reaching the window capture phase. Only the `morph` path and the macOS WebKit and Chromium legs carry it; the Linux WebKit
legs walk the hero path only.

| leg | arm | root listeners of the 7 types | events of the 7 types per walk (median) |
|---|---|---|---|
| WebKit macOS 390 | base | 14 | 490 |
| WebKit macOS 390 | cand | 0 | 485 |
| WebKit macOS 1280 | base | 14 | 667 |
| WebKit macOS 1280 | cand | 0 | 658 |
| Chromium 390 | base | 14 | 783 |
| Chromium 390 | cand | 0 | 794 |
| Chromium 1280 | base | 14 | 808 |
| Chromium 1280 | cand | 0 | 826 |

By type (WebKit macOS 390 base, median): animationiteration 151, transitionrun 79, transitionstart 71, animationstart 66,
transitionend 60, animationend 39, transitioncancel 19. Every one of the 7 is dispatched, so there is no type to leave
registered. The event count is the same with and without the flag (the events do not depend on the listener).

The probe rest-state verdicts are diagnostic and not the gate. The macOS legs report differences between base and cand
that differ from run to run: run 40122201939 has 88 new units at 390 (84 coverage, 4 content) and 0 at 1280; run 40124553279 has 42 at 390
(coverage) and 43 at 1280 (42 coverage, 1 content). Run 40126773924: 86 at 390 (84 coverage, 2 content), 0 at 1280, 0 on Chromium. The macOS 390 morph path shows new coverage units in
all three runs (88, 42, 86), the 1280 path in one (0, 43, 0). Two readings fit and the probe cannot tell them apart: witness noise,
or the flag removing main-thread work so that fewer samples land in a nav step (INFERRED, unchecked). An A/A run (a flag
that changes nothing) would decide; it is in the report as a dispatch.
Chromium 1280 had 1 new content unit in the first run and 0 in the second.
docs/team/tools/trajectory-probe.md lists the macOS witness nav reads as noisy. The breakpoint gate decides.

## Chromium

Chromium also dispatches these events (table above), but the task is judged on WebKit. Chromium's counts are reported by
the lead's dispatches if wanted.

## Limits

- Playwright WebKit on macOS stands in for Safari; the recorder counts events at the window, not WebKit's own timeline records.
- The records-per-event factor 2 is from source (`EventTarget.cpp:313-357@862f17d`); the Simulator after-count is the
  check that it holds (dispatch).
- Counts are engine work, not felt smoothness; the phone is the user's step.
- The flag covers the root container. A portal into another container registers the types again.

## WebKit Simulator before/after (MEASURED)

Answer: the flag halves EventDispatch and cuts FunctionCall by a third on the iPhone Simulator scroll walk.
Lane: `webkit-sim.yml`, target rewrite, 430x775 at dpr 3, one macOS VM (job r1) with 2 passes per run, 50 px steps
(106 steps). Base run 40134016822, flag run 40134234199 (`engine.events:quiet`), both on `ci/react-root-quiet-events-gate`
at 2898fb298. Each run gave 1 VM x 2 passes (`fw run --runs 3` did not reach VMs), so the counts are n=2 passes per arm, MEASURED; the spread below is across those 2 passes. Summary: `results/react-root-quiet-events/sim-summary.json`.

| count (walk total) | base pass 1 | base pass 2 | flag pass 1 | flag pass 2 | change |
|---|---|---|---|---|---|
| EventDispatch | 1132 | 1099 | 529 | 527 | -53% |
| FunctionCall | 1646 | 1623 | 1045 | 1042 | -36% |

Per 500 px zone (11 zones, pass 1 / pass 2): every zone is lower with the flag; the largest base zone 0 goes
160/175 to 69/47 EventDispatch, zone 7 132/136 to 56/44, zone 10 40/48 to 18/18. The flag's two passes differ by at most 2
in the total, the base's by 33, so the drop (about 570 to 600 dispatches) is far beyond the pass spread.
The FunctionCall drop (about 600) equals the EventDispatch drop: each removed dispatch took its one listener call with it,
as `parentPairs` "EventDispatch>FunctionCall" predicts. The remaining EventDispatch (about 528) is the page's own
input and animation-frame listeners. Per-zone cells are quarantined by the Simulator determinism classes; the totals are
"stable". Gate with the flag on both engines: run 40128098292 passed.
