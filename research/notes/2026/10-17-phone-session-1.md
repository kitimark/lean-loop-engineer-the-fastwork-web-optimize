---
id: 2026-10-17-phone-session-1
kind: note
title: "Phone session 1: gap cells, WebKit counts and scripted frame timing on the real iPhone"
status: review
created: 2026-10-17
topics: [webkit, iphone, device, counts, frame-timing, gap-harness]
---

# Phone session 1

Question: do the Simulator's WebKit results hold on the real measurement iPhone (15 Pro Max, iOS 27.0.1, Safari 27.0.1), and
how do the original and the rewrite compare there? Data: `results/phone/2026-10-17-s1/` (README has the tables). Harness
commit is the one adding `packages/measure-webkit/src/device*.mjs`. Labels: MEASURED = on-device numbers in those files;
INFERRED = my reading.

## Method (CONFIRMED by the code)
- The phone is driven with ios_webkit_debug_proxy on ports of its own (list 9460, tabs 9461), never the Simulator lane's
  ports or the older proxy. One about:blank tab is navigated by `location.href` through the raw Web Inspector client
  (`wip.mjs`), with a reconnect after each navigation. Both sites are served by `serveTree` bound to the LAN interface; the
  address is never printed or stored (`redact` in `device.mjs`, unit-tested).
- Counts use the same profile as the Simulator lane (pinned clock, seeded `Math.random`, `Timeline` records, `LayerTree`
  census, `reduce.mjs` zones of 500 px, `classifyPasses` policy kMax 4, tMax 24).
- Frames: rAF-timestamp intervals while a time-based `scrollTo` runs at 800 px/s. SCRIPTED, not a finger swipe: no compositor
  momentum, 1 ms timestamp resolution.

## Results
- MEASURED: gap-device, 8 of 8 cells agree with Lean (all unreachable) and with the Simulator; the phone reports the
  ceiling of a fractional width and never realizes it. The one difference from the Simulator is `dark` (the phone is in Dark
  appearance), which is not a gap question.
- MEASURED: original counts, phone against Simulator: Composite 213 and EventDispatch 107 identical; FireAnimationFrame 731
  vs 726; Style 654 vs 716, Layout 622 vs 696 (9 to 11 % lower on the phone); Paint 1575 vs 1342 (+17 %); TimerFire 35 vs 136.
  Phone passes are stable (Style 652 to 657, Paint 1546 to 1616); 34 deterministic / 13 stable / 25 quarantined classes.
- MEASURED: scripted scroll, original: 28.7 frames per 100 over 34 ms, 22.9 per 100 over 50 ms, longest 164 ms. All of it
  sits in the first 3000 px (98 to 100 per 100 over 34 ms, median interval 72 to 90 ms); from 3500 px on every interval is 17 ms.
- MEASURED: the rewrite is a placeholder page; it has 0 frames over 50 ms of 2700 and one over 34 ms, with 162 style
  recalculations against the original's 654. Not like-for-like: its document and layer count are far smaller.
- INFERRED: the original's jank zone coincides with its heavy paint and layout zones (Paint 185 to 231 per zone in
  0 to 1500 px on the phone); the cause is not isolated here.

## Limits and open items
- The primary metric on a finger swipe was not measured; it needs the user's hand (lead to decide).
- Heat: battery temperature stayed 32 C; the iOS thermal state is not readable, so a thermal throttle cannot be excluded
  (INFERRED: unlikely with 5 to 6 min blocks and no rise in battery temperature).
- The Simulator comparison has 2 passes (CI), the phone 3; the original ran 1 session on the phone.
- The rewrite measurement must be repeated on a finished rewrite.
