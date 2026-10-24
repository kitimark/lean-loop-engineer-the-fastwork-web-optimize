---
id: 2026-10-2x-morph-reopen
kind: note
title: "Why the end-of-page panel re-opens and pushes the scroll back: a 1 px finger direction flip re-opens it, and an overscroll pin fights the rubber band"
status: review
created: 2026-10-24
topics: [morph, end-of-page, touch, scroll, pin, rubber-band, webkit, phone]
---

# Why the end-of-page panel re-opens and pushes the scroll back

Rewrite paths are under `apps/site/src/parts/`. "N2" is the original's
`snapshot/site-pretty/_app/immutable/nodes/2.DyWL8TcE.js`. Phone numbers come from the real-iPhone session of
2026-10-24, 13 passes (`phone/rec-1` is left out because it never reached the end, y max 1736). The counting scripts
are uncommitted scratch scripts in a folder named `mro/`.

## Question

At the end of the page the morph panel (`.start-selling-platform`) opens, closes and opens again many times per pass.
While it is open, scrollY jumps back against the user. The throttle note (`10-2x-scroll-throttle-parts.md`, step 7)
measured 8-41 fade onsets per pass and left the cause untraced. What makes the panel re-open, and what pushes the scroll
back?

## Answer first

- The 100 ms scroll throttle does not cause the re-opens. Opening and closing do not depend on scrollY, scroll events
  or timers. Only the sign of each touchmove or wheel delta matters. CONFIRMED in code (rewrite and N2).
- A "fade onset" is a close start, not a re-open. `--morph-fade` is 1 when closed and 0 when open, so "fade leaves 0"
  catches the first open and then each close. Onsets = 1 + close starts in all 13 passes. MEASURED.
- Every close followed a downward finger drag, which scrolls toward the top (211 of 213). Every re-open followed an
  upward drag (201 of 202). None followed a rubber-band bounce, momentum after a lift, or a restore write. MEASURED.
- While the panel is active, a finger move of 1 px or more flips its target, with no arm check and no hysteresis. In the
  passes with high counts, 99 re-opens came less than 680 ms after a close, often within the same drag. MEASURED.
- The scroll push-back is the pin fighting the rubber band. The pin is usually taken from an overscroll scrollY above
  the real end (5227): pins at opens from rest span 5227-5330, median 5258, and 126 of 148 are above 5228. After the
  lift the page springs back to 5227 and the restore writes the pin again. That gives the 5292 / 5227
  alternation, with a median size of 20-78 px. MEASURED.
- For the faithful `morph.tween` and `morph.mount` variants that the phone arms ran, the rewrite makes the same
  decisions as the original. Other variants differ: `waapi` and `waapi-scoped` use `createWaapiDriver`, the band
  variants route touches through `touchHub` (`morph.tween/index.tsx:55-58`), and `scroll-lock` adds an overflow lock
  (`scrollLockOf`, `:96-103`). The fight and the 1 px flip are original behaviour, so every fix below is a look or
  behaviour change for the user to review. The one exception is a cost cut. CONFIRMED in code.

## State machine

Geometry: armed means the platform is at least 0.45 of the viewport tall and its bottom is at most 8 px below the
viewport bottom. The viewport height is `visualViewport.height`, or `innerHeight` as a fallback. CONFIRMED
(`morph.tween/logic.ts:49-51`, `morph.tween/driver.ts:112-117`, `morph.tween/index.tsx:35`; N2:13045-13046). The
platform is the last child of `<main>` and there is no footer, so armed means about `scrollY >= maxY - 8`. INFERRED:
the trailing margin was not checked. Overscroll keeps the arm true. A toolbar expand shrinks vh by about 40 px and can
un-arm a still page. INFERRED: the recorder reads `innerHeight` once at the end of each pass (815, 775, and 777 for
mpt), no in-pass toolbar step is measured, and the code reads `visualViewport.height`. The arm is tested only for a
push while the panel is inactive.

| State | Event | Condition | Action | Rewrite | N2 |
|---|---|---|---|---|---|
| far | IntersectionObserver entry (200 % margin) | intersecting | near; attach capture wheel (non-passive), touchstart (passive), touchmove (non-passive) | `driver.ts:199-203`, `:139-145`; `index.tsx:61` | 13060-13066, 13079-13087 |
| near, idle | touchstart | none | `touchY = touches[0].clientY` | `driver.ts:126-128` | 13052-13054 |
| near, idle | touchmove or wheel | delta = prevY − y ≥ 1 and armed | **open**: pin = scrollY; preventDefault; goal 1, 680 ms tween | `driver.ts:118`, `:129-136`, `:171-195`; `logic.ts:44-46`, `:85-89` | 13048, 13055-13058, 13024-13036 |
| near, idle | touchmove or wheel | 0 < delta < 1 and armed | pin = scrollY; preventDefault; no goal change | `driver.ts:118`, `:134` | 13048, 13058 |
| near, idle | same | delta ≤ 0, or not armed | ignored; default not prevented | `logic.ts:54-56` | 13048 |
| active (target or value > 0.001) | touchmove or wheel | delta ≤ −1 | **close**: goal 0; preventDefault; pin kept | same | same |
| active | touchmove or wheel | delta ≥ 1 | **re-open**: goal 1 from the current value; no arm check; pin kept | same | same |
| active | touchmove or wheel | \|delta\| < 1, or already heading to that goal | nothing; default still prevented | `logic.ts:86` | 13025 |
| active | each scroll or resize frame | scrollY ≠ pin | `scrollTo({top: pin, behavior: 'instant'})` | `driver.ts:205-207`; `index.tsx:38`, `:63`; `engine/scroll.ts:96-101`, `:131-137` | 13077-13078, 13090 |
| closing | tween frame | value ≤ 0.001 and target 0 | inactive; listeners kept while near | `driver.ts:153-169` | 13020-13023, 13074 |
| any | IntersectionObserver exit | not intersecting and inactive | detach listeners | `driver.ts:146-153` | 13067-13074 |

The table cites the code report. I checked by hand the arm (N2:13045-13046), the pin take (N2:13050, 13058;
`driver.ts:122`, `:134`), `touches[0]` (N2:13053, 13056; `driver.ts:127`, `:130`) and the restore (N2:13078;
`driver.ts:205-207`).

- There are no timers, no hysteresis beyond the 1 px dead zone (`dir`, `logic.ts:44-46`; Lean `Fw.Parts.MorphTween.dir`,
  `deadzone`), no scroll-direction check and no touchend handling.
- The pin is sampled only when a push starts from inactive. It can be an overscroll value. In CI Simulator run
  40065281372 it was 5346 against a maxY of about 5227-5267, which no resting scroll position reaches.
- One difference from the original: `App.tsx:51` mounts `MorphMount`, which attaches a second non-passive capture wheel
  and touchmove pair while near (`morph.mount/index.tsx:74-83`). It prevents the default only when delta > 0 and armed,
  which the tween already prevents. So the result is the same, plus one more `getBoundingClientRect` per touchmove.
  `App` passes no `isActive`, so the second pin never writes (`morph.mount/index.tsx:22`, `:107-110`). The throttle
  note's step 5, "both pins call `scrollTo`", is wrong for `App`: only the tween pin writes. CONFIRMED in code.
- Order: N2 runs the hero check and the pin in one engine callback (N2:13078). The rewrite registers the pin on its own
  at order 110, with the same target and condition. CONFIRMED in code.

## What the phone data shows

Counting rules (the names in the tables below):

- **Close start**: the first frame where fade starts rising after not rising. The first open (fade from unset 0 to
  1000) does not count.
- **Re-open**: the first frame where fade starts falling after a close.
- **sameDrag**: no touchend between the opposite event and this one.
- **newRest**: a touchend in between, and y still for at least 6 frames before the event.
- **newMoving**: a touchend in between, but y moving before the event.
- **noMove**: no touchmove in the 250 ms before the event.
- **Reversal** (same rule as the throttle note): a move of at least 20 px against the previous move, with either frame
  at y ≥ 5167.
- **Fight**: a reversal of one of two kinds. A restore lands within 1 px of the pin while the panel is open. The pin is
  y at the open frame or the 2 frames before it, so it is an estimate. A spring-back is a move up the page with the
  finger up, from above 5228 to 5225 or more.
- **Finger reversal**: a fingerDrag or panOffPin, with the finger down. panOffPin means the move leaves the pin.
- **Size**: \|dy\| of the frame that reverses.

Per pass (MEASURED):

| rec | arm | onsets | closes newRest / sameDrag / newMoving / noMove | re-opens sameDrag / newRest / newMoving | re-opens < 680 ms after close | reversals fight / finger / other | median px all / fight / finger |
|---|---|---|---|---|---|---|---|
| phone/rec-4 | original p2 | 9 | 8/0/0/0 | 1/2/4 | 0 | 6/2/0 | 36/36/93 |
| rec-1 | original | 8 | 6/0/1/0 | 0/2/4 | 0 | 8/5/0 | 58/58/95 |
| rec-4 | original p2 | 14 | 10/0/1/2 | 1/7/4 | 4 | 8/4/0 | 52/48/60 |
| phone/rec-2 | rewrite | 6 | 5/0/0/0 | 0/0/4 | 0 | 5/5/0 | 43/23/55 |
| rec-2 | rewrite | 9 | 8/0/0/0 | 1/2/4 | 0 | 13/4/0 | 63/63/122 |
| rec-2b | rewrite | 41 | 39/1/0/0 | 21/9/10 | 23 | 23/8/0 | 57/34/61 |
| phone/rec-3 | look | 6 | 5/0/0/0 | 1/1/2 | 0 | 9/2/0 | 33/33/114 |
| rec-3 | rewrite+lift | 9 | 8/0/0/0 | 1/2/4 | 0 | 3/2/0 | 30/20/116 |
| rec-3b | rewrite+lift | 20 | 19/0/0/0 | 11/3/4 | 10 | 7/3/0 | 21/21/55 |
| rec-3c | rewrite+lift | 17 | 16/0/0/0 | 10/4/2 | 12 | 4/2/0 | 78/78/120 |
| rec-3d | rewrite+lift | 35 | 33/0/1/0 | 27/1/5 | 28 | 11/5/2 | 62/39/71 |
| rec-thr | hero.exit:threaded | 16 | 15/0/0/0 | 7/4/3 | 8 | 7/2/0 | 44/38/97 |
| rec-mpt | morph.panel:threaded | 36 | 31/3/1/0 | 21/8/5 | 14 | 9/5/0 | 56/40/56 |

What came before each event (MEASURED):

- Closes: the finger was down with a downward drag in 211 of 213. In 203 it was a new touch on a page held still for at
  least 6 frames (209 of 213 had the page still for 6 frames or more), and velocity was 0 every time. Many closes
  started above 5227, on the pin: rec-2b 33/40, rec-3d 23/34, mpt 23/35, rec-1 6/7.
- The 2 noMove closes in rec-4 had their last touchmove 257 ms and 613 ms before. INFERRED: the close shows in fade only
  once r drops below 0.55.
- Re-opens: the finger was down with an upward drag in 201 of 202.
- Median time from close to re-open: about 9.9-13.5 s in phone/rec-2, -3, -4 and rec-1, 1.3-2.6 s in rec-2, rec-3 and
  rec-4, and 0.28-0.85 s in rec-2b, rec-3b/c/d, thr and mpt.
- Median time between close starts: 0.8-2.2 s in the high-count passes, 3-16 s in the others.

Reversals by cause, all 13 passes pooled (164 in total, 113 with the panel open; MEASURED):

| cause | n | finger down in the 6 frames before | down page / up page | median y0 − 5227 | median \|v\| before (px/s) | median ms since last fade event | median px |
|---|---|---|---|---|---|---|---|
| restore to pin | 63 | 48 | 53/10 | 12 | 87 | 146 | 33 |
| spring-back | 50 | 41 | 0/50 | 63 | 0 | 109 | 44 |
| panOffPin | 7 | 7 | 0/7 | 27 | 0 | 518 | 67 |
| fingerDrag | 42 | 42 | 0/42 | 42 | 0 | 742 | 71 |
| finger up, other | 2 | 2 | 1/1 | 57 | 827 | 720 | 286 |

- 31 restores jump from 5227 up to the pin, 9 of them within 10 frames of a spring-back. MEASURED.
- 41 of 50 spring-backs come within 6 frames of a lift. They are the release, not momentum. MEASURED.
- Only 10 of 164 reversals are 40 ± 2 px, so the toolbar step is not a main cause. MEASURED.
- With the panel closed and the finger up, long rests (30 frames or more) occur in 4 passes, at 5227-5269. MEASURED.
  INFERRED: the end is 5227 with the toolbar collapsed and 5267 expanded.
- y holds still above 5267 with the finger up for up to 63 frames (rec-1, 5292), and at 5262 for 366 frames in mpt.
  MEASURED.

Limits:

- The recorder reads `maxY` once at the start and `viewport.h` once at the end
  (`packages/measure-webkit/src/device-record.mjs:23`, `:61`), so the viewport height per frame is unknown.
- While r is above 0.55 the fade stays at 0. A close that is re-opened before r falls below 0.55 does not show, so the
  close and re-open counts are lower bounds.
- Onset counts follow how the user moved in each pass, not the arm. INFERRED: they cannot rank arms.

## Causes ranked

1. **The 1 px direction flip while active (the re-opens).**
   - Mechanism: while active, any touchmove with delta ≥ 1 retargets to open and delta ≤ −1 retargets to close. There is
     no arm check, no touch identity and no minimum distance (`driver.ts:129-136`, `logic.ts:44-46`, `:85-89`;
     N2:13055-13058).
   - Code: CONFIRMED.
   - Data: every re-open followed an upward drag (201/202). 99 came within 680 ms of a close, and 21-27 per pass in
     rec-2b, rec-3d and mpt came within the same drag. MEASURED.
   - Whether the user meant to flick down and then up, or the finger wobbled, is not known. INFERRED either way.
2. **The overscroll pin against the rubber band (the push-back).**
   - Mechanism: the pin is taken from scrollY at the open frame, which is often an overscroll value. With the finger
     up, WebKit springs the page back to the real end. The next scroll or resize frame sees scrollY ≠ pin and writes
     the pin again (`driver.ts:205-207`; N2:13078). WebKit does not stop a user deceleration for a script `scrollTo`
     (`RemoteScrollingCoordinatorProxy.cpp:172-192`, as cited in `10-2x-touch-lock-page-end.md`).
   - Code: CONFIRMED.
   - Data: 63 restores and 50 spring-backs out of 164 reversals, and 31 direct 5227-to-pin jumps, 9 of them within 10
     frames of a spring-back. MEASURED.
3. **Closes swallow the drag back up (the felt "stuck at the end").**
   - Mechanism: the first downward drag after an open only closes the panel. The pin stays and default stays
     prevented until the 680 ms tween ends, so the page does not move for that drag (state machine, "close" row).
   - Code: CONFIRMED.
   - Data: 203 of 213 closes were a new touch on a still page, and many started on the pin. MEASURED. That the user
     felt this as being stuck is INFERRED.
4. **The toolbar moves the arm threshold.** It gates only the first open after a full close. An expand can block an
   open, a collapse allows one. It cannot close an open panel (`logic.ts:49-51`, `index.tsx:35`; N2:13045-13046).
   CONFIRMED in code. The effect on the data is small: only 10 of 164 reversals are near 40 px. MEASURED.
5. **Spurious clientY jumps.** When the first finger lifts, `touches[0]` becomes another finger. A toolbar change can
   also shift a still finger's clientY. Either gives a large delta of either sign (`driver.ts:130`; N2:13056). INFERRED,
   not measured.

Not causes: momentum, a bounce crossing the arm (overscroll only arms), a restore retargeting the panel, and the
100 ms throttle. With no finger down there are no touchmoves, so the state cannot change. The phone shows 0 of each.
MEASURED.

## Fix candidates ranked

For the faithful `morph.tween` and `morph.mount` variants that the phone arms ran, the original has every behaviour in
the cause list (other variants: see "Answer first"). A fix that changes them belongs in the look-change class that the
user set on 2026-10-21, and needs the user's visual review before it ships.

1. **Clamp the pin to the real end.** Change: `pinned = min(scrollY, scrollHeight − vh)` at the open, with vh read in the
   same frame.
   - Same look: no. The original holds the page in overscroll while open. The clamp holds it at the end instead, so the
     page stops springing between 5292 and 5227. Look change.
   - Lean: extend `Fw.Measure.TouchLock` with a pin model and prove that a clamped pin gives 0 spring-back fights when
     the engine clamps resting scrollY to maxY. Add golden vectors for `driver.ts`.
   - Measurement: CI Simulator touch push (`touch-push.mjs`) per arm (original, rewrite, clamp) with fights and
     displaced counts. Then a phone pass that replays a recorded finger path, as the user asked on 2026-10-21.
   - Relation: this is `touch-lock-windows` item (2) seen from the site side. That task reads the stored pin through
     the page hook. This fix changes what gets stored. Run it after `touch-lock-windows` lands, so the fight counter
     reads the real pin.
2. **Hysteresis on the flip while active.** Change: after a close, re-open only after a drag of N px or more upward in
   one direction (or only on a new touch). Same for the reverse. N comes from the phone wobble distribution.
   - Same look: no. The panel no longer reacts to 1-N px moves. The tween and its look stay the same. Behaviour change.
   - Lean: a reducer over the delta sequence in `Fw.Parts.MorphTween`. Prove that a sequence whose partial sums stay
     inside (−N, N) never flips the target. Prove that the reducer equals the original whenever every delta is at least
     N in size, so only small moves change. Add golden vectors.
   - Measurement: replay the recorded finger paths of rec-2b, rec-3d and mpt in the CI Simulator, counting re-opens per
     pass for the original and for the candidate. Then a phone check with the user.
   - Relation: it uses the same `touch-push.mjs` harness as `touch-lock-windows`. It does not touch `engine.scroll`, so
     it is independent of `unthrottle-preset`.
3. **Release the pin when a close starts.** Change: on a close, drop the pin and stop preventing default, so the drag
   back up scrolls at once while the panel fades out.
   - Same look: no. The page moves during the 680 ms close. Behaviour change.
   - Lean: a state-machine lemma that no restore writes after the close push, and that the open path is unchanged.
   - Measurement: phone replay. Displaced frames after the close start should drop to 0.
   - Relation: like fix 1, it changes what `touch-lock-windows` measures as the lock window, so it comes after that
     task.
4. **`engine.scroll:unthrottle` (task `unthrottle-preset`).** Change: none here; that task ships it.
   - Same look: INFERRED same, per that task.
   - Effect: fresher scrollY for the pin take and the arm. It cannot reduce re-opens, because no open or close
     condition reads scrollY. The phone with lift still shows 3-11 fights per pass. MEASURED.
   - Relation: it is a cofactor for fix 1, not a replacement.
5. **Track the touch by `identifier`.** Change: read the touch that started the gesture instead of `touches[0]`.
   - Same look: the same for one finger, but behaviour differs with two fingers. A behaviour change, unmeasured.
   - Lean: a lemma that the single-touch traces equal the original.
   - Measurement: a multi-touch Simulator case. Low value until data shows multi-touch events.
6. **Drop the redundant `MorphMount` listener pair in `App`.** Change: do not attach its wheel and touchmove listeners
   while the tween owns the gesture.
   - Same look: yes. Its preventDefault set is a subset of the tween's, and its pin never writes. CONFIRMED in code.
   - Effect: it saves one `getBoundingClientRect` per touchmove. It does not touch the re-opens.
   - Lean: prove that the mount's prevent condition implies the tween's prevent condition, and that the mount pin is
     dead when `isActive` is absent.
   - Measurement: the breakpoint gate on both engines, plus Chromium and WebKit counts on CI.

## Open questions

- Is the flick down and then up deliberate? A phone pass with the user asked to hold still at the end would separate
  wobble from intent. That is a user-only step.
- What is the exact maxY per frame? The recorder reads it once. Recording `scrollHeight − visualViewport.height` per
  frame would confirm 5227 and the 40 px toolbar shift.
- Does WebKit clamp a script `scrollTo` above maxY during a rubber band, or hold it? The phone shows y held above 5267
  with the finger up for up to 63 frames. The engine source path for that was not read.
- Every line number above 12700 in the `logic.ts` header is stale against the current snapshot: pointer cut 13026 is
  13017, active 13030 is 13019, tween frame 13033-13035 is 13020-13023, push 13036-13053 is 13024-13036, and armed and
  taken 13065-13069 is 13045-13048. CONFIRMED (N2:13017, 13019, 13020, 13024, 13036,
  13045, 13048 read).

## Sources

- `apps/site/src/parts/morph.tween/driver.ts`, `logic.ts`, `index.tsx`; `morph.mount/index.tsx`, `logic.ts`,
  `listen.ts`; `engine/scroll.ts`; `apps/site/src/App.tsx:51`.
- `snapshot/site-pretty/_app/immutable/nodes/2.DyWL8TcE.js:12699` (fade), `:13017` (`--morph-fade` write),
  `:13019-13090` (morph driver).
- `lean/Fw/Parts/MorphTween.lean` (`dir`, `armed`, `taken`, `active`, `fade`), `lean/Fw/Measure/TouchLock.lean`.
- `packages/measure-webkit/src/device-record.mjs:19`, `:23`, `:61`.
- Phone passes of 2026-10-24 (`results/phone/2026-10-24*`). CI Simulator run 40065281372.
- `research/notes/2026/10-2x-scroll-throttle-parts.md`, `research/notes/2026/10-2x-touch-lock-page-end.md`.
- Tasks `touch-lock-windows` and `unthrottle-preset` (`docs/team/work-graph.json`).
