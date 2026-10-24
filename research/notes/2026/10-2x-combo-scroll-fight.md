---
id: 2026-10-2x-combo-scroll-fight
kind: note
title: "Scroll fights the finger after a close and an immediate reopen: morph.end.release alone causes it, the pin then fights a native scroll the page cannot cancel; a hold bit fixes it"
status: review
created: 2026-10-25
topics: [morph, end-of-page, touch, scroll, pin, release, lean, chromium, replay]
---

# Scroll fights the finger after a close and an immediate reopen

Rewrite paths are under `apps/site/src/parts/`. Replay runs are on CI Chromium (CPU throttled 6x), workflow
`device-replay.yml`, job `combo`. The phone record `bug-rec-4.json` stays local and is not copied.

## Answer first

- The user's words (2026-10-25): closing the end-of-page and opening it again at once makes the page scroll back while
  the end-of-page has not closed yet. Reproduced on CI Chromium: a close that lets the page follow the finger, then a
  reopen, makes the page jump against the finger. MEASURED, run 40130709244, build `before` (the code of `45efb0d5a`,
  without the fix): with the user's 8 flags 11 of 16 replays fought (script `scrollTo` writes against the finger, 58
  while the finger was down and 67 after the lift, 8 direction reversals with no finger down, 24 single-frame script
  jumps of at least 20 px, the largest 238 px).
- Minimal flag set: `morph.end.release:on` alone. MEASURED, same run: release alone fought in 13 of 16 replays; clamp
  alone, flip alone and the user's flags minus release fought in 0 of 15 each; dropping any other one flag (arm-late,
  unthrottle, nav, either countdown, clamp, flip) still fought in 10-12 of 15. `morph.mount:arm-late` and
  `engine.scroll:unthrottle` are not needed: the three bricks alone fought in 12 of 16 replays, with arm-late 11 of 15, with
  unthrottle 11 of 15, with both 11 of 15. The lead's hypothesis (arm-late and unthrottle are part of the cause) is refuted; "release drops the pin at
  the close start" is right and is not the bug (see Cause).
- Cause, CONFIRMED by the code and by the traces (below): with release a close move is not prevented, so the page scrolls
  natively with the finger. Every later `touchmove` of that touch is then not cancelable, so `preventDefault` does
  nothing. A reopen in such a move still starts the open tween and pins the page at the scroll position it reads, and
  the pin writer (`morph.tween` through `registerScroll`, the only one in the app) writes that position on every scroll
  frame while the finger and the fling move the page the other way. The pin is stale as soon as the page moves, so each
  write is a jump back ("it go up").
- Fix: one bit, `held` (the last move was prevented and the browser let that stand). The frame writer writes only while
  `held`; a move that brings `held` back re-pins where the page is. Active only with `morph.end.release` on. Lean
  `Fw.Parts.ComboScroll`, TS `morph.tween/end.logic.ts`, golden `packages/contracts/golden/parts/combo-scroll.jsonl`
  replayed by `apps/site/src/registry/combo-scroll.test.ts`.
- After the fix, same run, build `after`: every arm that has release (the user's flags, the three bricks, release alone,
  every drop-one arm) had 0 script writes, 0 no-finger reversals and 0 script jumps of at least 20 px in all 15-16 replays.
  The page still reverses with the finger when the finger turns round (in the user's flags, the three bricks and release
  alone: 57 reversal pairs of at least 20 px, all with a finger down, none without; before: 98, 8 of them with no finger). MEASURED.

## Reproduction

| What | Detail |
| --- | --- |
| Page | the rewrite built with each flag set (`apps/site/scripts/build.mjs --configs none --config ...`), served by `combo-serve.mjs` |
| Input | CDP `Input.dispatchTouchEvent`, 60 Hz paths from committed profiles, CPU throttled 6x |
| Profiles | `user-bug-1025.json` (the 31 strokes of the phone pass, compiled; no timestamps or raw samples), and scripted `user-bug-1025-reopen-{flick-gap8,flick-gap20,flick-gap32,same-touch,same-touch-slow}.json` from `combo-profile.mjs` |
| Recording | per animation frame: scrollY, finger down, morph value; every page `scrollTo` call with the position it started from and the finger state; every `touchmove` with `cancelable` and `defaultPrevented` |
| Verdicts | `combo-metrics.mjs`: reversals of scrollY between adjacent frames with no finger (the phone analysis), single-frame jumps (two adjacent opposite legs of at least 20 px), script jumps (a jump with a page `scrollTo` between its frames), script writes by finger state. TS stand-in, not yet a Lean function |

Runs (all `device-replay`, branch `ci/device-replay`):

| Run | Commit | Result |
| --- | --- | --- |
| 40128362520 | `45efb0d5a` | failed at the build step: `morph.countdown:strip requires hero.countdown:strip`; the drop-one arm for hero.countdown now drops both |
| 40129128571 | `510e82050` | before/after, first harness (the page started at the end with a smooth scroll still running, so some replays did not open the morph); the same ordering of arms |
| 40130709244 | `b557cd0a0` | before/after with an instant start and a morph-ran column: the numbers in this note |

Bisect table, run 40130709244, replays that fought / replays (5 scripted legs x 3 repeats + the recorded path once):

| Arm | before | after |
| --- | --- | --- |
| default (all faithful) | 1 / 16 (recorded path only) | 1 / 16 (same) |
| user's 8 flags | 11 / 16 | 0 / 16 |
| clamp + flip + release | 12 / 16 | 0 / 16 |
| release alone | 13 / 16 | 0 / 16 |
| clamp alone, flip alone | 0 / 15, 0 / 15 | 0 / 15, 0 / 15 |
| user's flags minus release | 0 / 15 | 0 / 15 |
| user's flags minus arm-late | 12 / 15 | 0 / 15 |
| user's flags minus unthrottle | 12 / 15 | 0 / 15 |
| user's flags minus nav, minus morph.countdown, minus both countdowns, minus clamp, minus flip | 11, 11, 12, 12, 10 / 15 | 0 / 15 each |
| bricks + arm-late, + unthrottle, + both | 11 / 15 each | 0 / 15 each |

"Fought" = at least one script write that moved the page, a no-finger reversal or a script jump. The default arm's one
fighting replay is the recorded path at the page end: the faithful page pins at the end and writes against the fling. It
is the original's behaviour and unchanged by design (hold acts only with release).

The recorded phone path (open loop: Chromium's fling is not iOS momentum) fought in the same way: user's flags 31 writes
with the finger down and 5 after the lift, 10 script jumps up to 238 px, before; 0 after. Playwright WebKit: not run.
Playwright's `Touchscreen` has `tap` only, so no native touch drag exists to replay on that lane (INFERRED from the API;
the phone check is the user's step).

## Cause, with the traces

CONFIRMED, one scripted trace (same-touch, local debug run, not a result; the CI numbers above are the results):

1. Finger up at the page end: the morph opens, pin 5188 (the page end).
2. Finger down in the same touch (release on): the close push is not prevented (`prevent: false`), the tween closes and
   the page follows the finger from 5188 to 4846. The `touchmove` events from here are `cancelable: false`.
3. Finger up again: the reopen move is `prevent: true` but not cancelable. The open tween starts and the pin becomes the
   scroll position read in the handler (4884.5).
4. Every scroll frame writes 4884.5 while the finger pushes the page down: 4927, 4899, 4913, 4898 ... (a jump of 14-42 px
   per frame). After the lift the writes continue against the fling for about 700 ms.

Code facts, CONFIRMED by reading: before the fix `moveStep` applied the pin as `pinAfter` (the scroll position when
`free`, that is release and a close was started) and `frameOut` wrote `min(pin, maxY)` whenever the morph was active and
not free; neither looked at `Event.cancelable`. `preventDefault` on a non-cancelable event does nothing and Chromium
logs "Ignored attempt to cancel a touchmove event with cancelable=false, for example because scrolling is in progress and
cannot be interrupted" (`third_party/blink/renderer/core/dom/events/event.cc:119-133@f842f52`). The page-level scroll
writers are `morph.tween` (`driver.ts` `pin()` and `waapi.driver.ts`), `morph.mount` (re-pin, built without `isActive` in
`App.tsx:51`, so it never writes), `hero.cue` (click), `people.deck` (click) and the stage; in the app `morph.tween` is
the only pin writer (`registry/combo-scroll.test.ts` pins this).

The lead's hypothesis, point by point:

| Hypothesis | Verdict |
| --- | --- |
| release drops the pin and stops `preventDefault` at the close start | CONFIRMED and intended; no write between the close start and the reopen (Lean `release_quiet`; MEASURED: the writes start at the reopen) |
| a per-frame writer still writes the old pin during the close | refuted: `frameOut` returns nothing while release and a close was started |
| two writers with different targets alternate | refuted for the app: one writer; `morph.mount` repin is inert |
| flip needs a new touch or 16 px, so the reopen may not count | not the cause: the reopen counted in every trace (the new touch or 16 px was there); the pin it set was the problem |
| arm-late's passive mode and unthrottle's read timing widen the window | refuted by the bisect: release alone fights, dropping either leaves the fight |
| the touch cannot be cancelled, so the pin fights native scroll | CONFIRMED (not in the hypothesis): the cancelable bit |

iPhone: Safari also makes `touchmove` non-cancelable once scrolling has started, and a touch that starts during a
momentum scroll can be non-cancelable at its first move (INFERRED from the Chromium behaviour and the user's report; not
measured on the phone, the user's check decides). The phone record supports the mechanism: all 55 single-frame reversal
pairs with both legs of at least 40 px happen while the morph is open (10) or tweening (45), none while it is closed
(MEASURED on `bug-rec-4.json`, local).

## The model and the fix (Lean `Fw.Parts.ComboScroll`)

`MorphEnd.step` stays unchanged. The wrapper `wstep h w e c` takes the browser's cancelable bit `c` per event and keeps
`held`:

- A move holds the page when the step prevents it and `c` is true.
- The frame writer writes only while `held`. A move that brings `held` back re-pins at the scroll position it reads.
- All of this applies only when `morph.end.release` is on; otherwise `wstep` is `step`.

Proved (all in `ComboScroll.lean`, axioms checked by `check.sh`):

| Statement | Theorem |
| --- | --- |
| release off: the wrapper is the inner reducer, event by event and over a trace | `wstep_off`, `faithful_w` |
| open and close decisions are those of the inner reducer: `prevent`, `goal`, `flip` and the state they read, from any inner state that agrees up to the pin | `wstep_prevent`, `wstep_goal`, `wstep_flip`, `wstep_core`, `step_core_pin`, `wtrace_decisions` |
| the wrapper only removes writes | `wstep_write_sub` |
| a write needs `held` | `fix_write_held` |
| no script write against a native scroll: after a move that is not held, every frame writes nothing until the next move, at any frame rate | `native_quiet`, `cadence_w` (unthrottle) |
| a hold that returns re-pins at the position read | `rehold_pin`, `held_keeps_pin` |
| when every move is prevented and cancelable the wrapper equals the inner reducer (the original page) | `wrap_all_hold` |
| the bricks keep their theorems with the wrapper: the clamp bound, no write after a close start until a push to open, the close move is not prevented, the close starts the release | `wclamp_le`, `wrelease_quiet`, `wrelease_close_free`, `wrelease_starts`, `wrelease_rel` |
| arm-late's blocking gate does not change `held` where arm-late's invariants hold | `arm_late_holds` (with `MorphMountArmLate.late_same`) |
| one write per frame event | `one_write_per_frame` |

Witnesses (`#guard`): on the user's trace (open, close, reopen in a non-cancelable move) the inner reducer writes 4900
twice against the native scroll and the wrapper writes nothing; with a cancelable reopen both write the same.

Golden: `lean/scripts/ComboScrollGolden.lean` writes 4 traces (same-touch, momentum, held-reopen, plain-open) under all 8
brick picks; `apps/site/src/registry/combo-scroll.test.ts` replays them through the TS reducer (prevent, goal, flip, write,
pin, held) and checks the driver on a fake browser with a non-cancelable reopen.

## What the fix changes (look class)

`morph.end.release` already changes the look (class L, phone review pending). The fix adds: a reopen in a move the page
cannot cancel opens the morph and leaves the page to the finger; the pin returns at the next prevented, cancelable move.
So the open morph can sit over a page that has scrolled away from the end until the user touches again. The user's
review decides.

## Accepted limits and follow-ups

- CI Chromium replay stands in for the phone (the user reproduced on Chromium and Mac Safari too). In the `flick-gap*` legs
  the reopen touch itself was not cancelable from its first move (MEASURED, `moves` in the artifacts: `cancelable: 0`
  from the close on); the reason is INFERRED (a main thread behind the 6x throttle makes Chromium send the move as
  non-blocking), and it is the iPhone's situation. The phone re-check is the user's step.
- The three marks at y about 1859 (touch up, the toolbar changing the viewport height 788-812 px, morph open) are a likely
  separate mechanism: a held pin written while the browser moves the offset for the toolbar. No bisect arm can reproduce a
  toolbar. INFERRED; follow-up: a gate that skips a write on a frame whose viewport height changed.
- Only the `createTweenDriver` path is covered; `waapi` and `waapi-scoped` pin without the bit (follow-up).
- The faithful page keeps the original's pin against a fling at the page end (default arm, recorded path); a separate
  look-change brick would be needed to change it.
- The verdict functions in `combo-metrics.mjs` are a TS stand-in (not Lean); the engine's cancelable bit is an input of
  the model, not derived.

## Re-run

- CI: commit with `[ci:device-replay]` and push to `ci/device-replay` (the workflow triggers on that name only). Job
  `combo` builds this commit and `BEFORE` (the last commit without the fix, `45efb0d5a`, set in the workflow) with
  `apps/site/scripts/build.mjs --configs none` and one `--config` per search of `combo-arms.mjs configs bisect`, then replays
  the same arms on both; artifacts `combo-<leg>` hold `before/run.json` and `after/run.json` with every frame.
- One pass by hand: `node packages/measure-webkit/src/replay/combo-cli.mjs run --dist <site dist> --profile <profile.json>
  --arms "$(node packages/measure-webkit/src/replay/combo-arms.mjs arms fix)" --throttle 6 --frames --out out/combo`, then
  `combo-cli.mjs summary --in out/combo/run.json`.
- New committed profile of a phone record: `node packages/measure-webkit/src/replay/make-ci-profile.mjs --in rec.json --id
  user-x --out profile.json` (the strokes at 60 Hz; no timestamps or raw samples are kept).
