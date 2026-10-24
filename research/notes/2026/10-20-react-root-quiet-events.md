# react-root-quiet-events: the root listeners behind the WebKit EventDispatch excess

Task `react-root-quiet-events`. Answer first.

- CONFIRMED (CI run 40122201939, trajectory-probe, recorder `fw-debug=root-events`): the React root registers 14 listeners
  for the 7 animation and transition types (capture and bubble each) in every rewrite arm; all 7 types are dispatched in a
  walk of the page (WebKit on macOS 390: about 490 events, 1280: about 660; Chromium about 790 and 810). Hence
  about 2 EventDispatch and 2 FunctionCall records per event, the "batches of 2" of the Simulator pass.
- CONFIRMED by source: a root listener turns each of these events into 2 EventDispatch records (one per phase with a
  listener); with no listener, none. Events are enqueued and dispatched whether or not a listener exists.
- Variant `engine.events:quiet`: the root registers 0 of the 14 (MEASURED, same run: `registered` is `{}` in all 10 cand
  walks per engine and width), every other listener stays (Lean `quiet_keeps`, replayed against the real react-dom).
- NOT DELIVERED here, needs the lead: the WebKit Simulator EventDispatch and FunctionCall counts before and after over 3 runs
  and the breakpoint gate with the flag (commands in the report). Until then the count drop is INFERRED: `records_orig`
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

Golden `packages/contracts/golden/parts/react-root-quiet.jsonl` (104 lines), replayed by `quiet.golden.test.ts`: the
`registered` rows are compared with what the real `createRoot` registers on a recording container, with and without
`quietContainer`. `quiet.gen.ts` is generated from Lean (`#guard` against the file bytes in the module).

## Measurement (MEASURED, run 40122201939, diagnostic, 5 walks per arm)

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

The probe's rest-state verdicts are diagnostic and not the gate. The macOS legs report coverage-only differences
between base and cand (390: 84 coverage units, 4 content units in the morph path; 1280: undecided) and Chromium 1280 one
content unit. The flag registers nothing the page reads, so these are read as sampling noise of a slow runner; the second
push repeats the line to see whether they recur (see the handoff). The breakpoint gate decides.

## Chromium

Chromium also dispatches these events (table above), but the task is judged on WebKit. Chromium's counts are reported by
the lead's dispatches if wanted.

## Limits

- Playwright WebKit on macOS stands in for Safari; the recorder counts events at the window, not WebKit's own timeline records.
- The records-per-event factor 2 is from source (`EventTarget.cpp:313-357@862f17d`); the Simulator after-count is the
  check that it holds (dispatch).
- Counts are engine work, not felt smoothness; the phone is the user's step.
- The flag covers the root container. A portal into another container registers the types again.
