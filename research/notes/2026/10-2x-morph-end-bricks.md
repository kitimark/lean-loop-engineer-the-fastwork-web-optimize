---
id: 2026-10-2x-morph-end-bricks
kind: note
title: "Morph end bricks in Lean: A clamps the pin to the real end, B needs 16 px against the goal to flip, C releases the pin when a close starts; all 8 picks proved"
status: review
created: 2026-10-24
topics: [morph, end-of-page, touch, scroll, pin, rubber-band, lean, bricks]
---

# Morph end bricks in Lean

## Answer

- `lean/Fw/Parts/MorphEnd.lean` models the end-of-page morph as one reducer over browser events. With every brick at
  `faithful` it is the original event by event (`faithful_eq_orig`, PROVED).
- The three fixes from `10-2x-morph-reopen.md` are three parts, each `faithful | on`: `morph.end.clamp` (A),
  `morph.end.flip` (B), `morph.end.release` (C). Each brick changes one hook of the step, so the 8 picks compose in any
  order (`order_free`, PROVED) and add no refusal to any registry selection (`bricks_no_rules`, PROVED).
- `all_combinations` (PROVED) states, for every one of the 8 picks: it is in `Cfg.all`, its hooks do not depend on brick
  order, A's claim holds when A is on, B's when B is on, C's when C is on, and the registry stays clean.
- Goldens: `packages/contracts/golden/parts/morph.end.jsonl`, 3 cases × 8 picks plus a constants line, from
  `lean/scripts/MorphEndGolden.lean`.

## The model

N2 is the original's `nodes/2.DyWL8TcE.js`; the reducer restates lines 13017-13090 and the rewrite's
`apps/site/src/parts/morph.tween/driver.ts`. Events: `touchstart`, `touchmove` (finger y plus the page's
scrollY and the armed rect test read in the same handler), `wheel`, `scroll` and `resize` (one frame, with scrollY and
the real maxY), `tick` (a tween frame). Each event returns `preventDefault`, a push goal and whether it flipped an active
morph, and a `scrollTo` target. The tween is `Fw.Parts.MorphTween` unchanged.

## What each brick proves

| Brick | Change | Theorems (all PROVED) |
| --- | --- | --- |
| A clamp | the restore target is `min(pin, maxY)` read per frame | `clamp_le`, `clamp_le_trace`: no write above the frame's maxY. `clamp_rest`: at rest on the real end, no write. `faithful_fight`: without A that frame writes the overscroll pin back. `clamp_only_writes`: A changes no state and no non-frame output. `clamp_same_below`: same writes as the original whenever the pin is at or below maxY. |
| B flip | an active morph flips only on a new touch or after `flipN` = 16 px net travel against the goal | `flip_needs`: every flip under B had a new touch or a counter of at least 16. `flip_band`, `band_after_push`: a finger that stays in a band narrower than 16 px with no new touch never flips. `flip_same`: when every move is below the 1 px dead zone or at least 16 px, B decides exactly as without it. |
| C release | a close start drops the pin and stops `preventDefault` until the next open | `release_starts`, `release_close_free`: the close move itself is not prevented. `release_quiet`, `release_after_close`: after a close start no restore write until a push to open. `release_open_same`: a trace with no close start is the same with or without C. |

Event cadence: `cadence_final` and `cadence_trace` (PROVED) show that scroll and resize frames change no state and no
other event's output, so the bricks hold under `engine.scroll:unthrottle` or any other frame rate.

## Golden cases

Each case runs under all 8 picks; every line lists the events and, per event, `prevent`, `goal`, `flip`, `write`,
`active`, the tween value and the pin. The module's `#guard`s pin the headline rows.

| Case | Events | Original | With the brick |
| --- | --- | --- | --- |
| spring-back | open at scrollY 5292 (overscroll), frames at 5292, 5250, 5227, 5292, toolbar moves the end to 5267 | writes 5292 three times against the rubber band | A writes 5227 (5267 after the toolbar step), nothing once the page rests at 5227 |
| wiggle | open, then the finger moves 1 px back and forth 4 times, then 20 px back | 5 flips | B: 1 flip (the 20 px pull) |
| drag-back | open pinned at 5250, new touch drags back up 70 px, hesitates 10 px, pushes 20 px down | the close and every later move are prevented, frames write 5250 (5227 with A only) against the drag | C: close and the drag are free, no write until the re-open, the re-open pins at 5200 where the page is |

## Accepted limits

- The browser is abstracted: `scrollTo`, the rubber band and momentum are input events with their scrollY; WebKit's
  deceleration curve is not modelled.
- The near/far IntersectionObserver attach is not modelled; every trace starts with the listeners attached.
- The second scroll listener of `morph.mount` is not modelled.
- C stops `preventDefault` mid-drag. WebKit may keep a touch sequence non-scrollable once its first move was prevented
  (INFERRED); the measure task checks it.
- `flipN` = 16 is a named constant; the measure task tunes it from the recorded passes.
- Only the `createTweenDriver` path is covered; the `waapi`, `waapi-scoped`, `scroll-lock` and `band` variants of
  `morph.tween` use their own drivers (follow-up).
- `Fw.lean` imports and the `check.sh` golden job are wired by the lead (shared files).
