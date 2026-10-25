---
id: 2026-10-2x-combo-held-identity
kind: note
title: "The hold bit of the end-of-page pin reads defaultPrevented, not cancelable: a passive listener keeps cancelable true while preventDefault is ignored"
status: review
created: 2026-10-25
topics: [morph, end-of-page, touch, scroll, pin, release, passive, lean, chromium, replay]
---

# The hold bit reads defaultPrevented

Follow-up of `10-2x-combo-scroll-fight.md`. Rewrite paths are under `apps/site/src/parts/`. Replay runs are on CI Chromium
(CPU throttled 6x), workflow `device-replay.yml`, job `combo`.

## Answer first

- The rule is now: the frame writer of `morph.tween` may pin only while the last move was actually prevented, that is
  `Event.defaultPrevented` read after the handler's `preventDefault()` call (Lean `Fw.Parts.ComboScroll.holds`, TS
  `morph.tween/driver.ts` `move` and `end.logic.ts` `hold`). Before, the bit was `prevent && cancelable`; a passive listener
  (the band hub's `watch` mode, `morph.mount:arm-late` outside its band) keeps `cancelable` true while the browser ignores
  `preventDefault`, so the old bit could stay true over a native scroll. CONFIRMED by the specs and engine source below.
- Proved in Lean (`ComboScroll.lean`, `check.sh` green with the axiom check): the fix theorem and the brick theorems are
  kept with the new input; a passive delivery is never held (`holds_passive`), a non-cancelable one is never held
  (`holds_uncancelable`), a blocking cancelable one is held iff the step prevents (`holds_blocking`), and after a passive
  move every frame writes nothing until the next move (`passive_quiet`, `arm_passive_quiet`).
- Golden regenerated from Lean (48 rows: 6 traces x 8 brick picks, two new: `passive-reopen`, `other-prevented`) and replayed in
  `registry/combo-scroll.test.ts` twice: through the pure reducer, and through the real driver on a DOM-faithful fake event
  (`cancelable`, passive listener, an earlier listener that already prevented). Both equal the Lean writes and
  `defaultPrevented` event by event.
- waapi and waapi-scoped cannot be picked with morph.end.release:on (registry conflict in `morph.end.release/part.json`; Lean
  `Fw.Parts.ComboScroll.decided_no_release_waapi`: every link `Fw.Console.Compose.decide` returns resolves through
  `validate`, whose final state never selects both; `accepted_no_release_waapi`, `finish_refuses`). So the waapi pin writers
  never run with the hold rule needed. The conflict changes no runtime path of the 8-flag arms (they pick the default tween), so
  no new CI push. Site test: `part.json` carries exactly the rule the theorem takes as hypothesis (`waapiKeys`). The hypothesis
  that the registry holds this rule is a test (TS), the resolver theorem is Lean.
- Replay, MEASURED, run 40142598495 (device-replay, success; Lean run 40142598556 success): on the build of this commit, the
  user's 8 flags (arm `user`) and the same flags with every touchmove and wheel listener passive and one blocking no-op listener
  (arm `user+passive`): 11 of 11 replays each (6 profiles: flick-gap8, 20, 32, same-touch, same-touch-slow, recorded; 2 reps,
  recorded 1) had 0 script writes against a native scroll, 0 script writes in total, 0 no-finger reversals and 0 script jumps of
  20 px or more. The same holds for `release`, `release+passive` and the other 15 arms of the bisect set (0 writes in all passes).
- Limit, MEASURED: the replay does not discriminate old from new rule. The `before` build (`13f319e2a`, the cancelable rule)
  also had 0 writes in `user+passive` and `release+passive`. The passive arms did deliver cancelable moves that were not prevented
  (45 of 1157 moves in `user+passive`, 43 of 1310 in `release+passive`; in the non-passive arms `user` has 24 of 1142, INFERRED the
  close moves, which release does not prevent), but the reopen touch of every profile starts while the close fling still scrolls, so its moves are not
  cancelable (the timeline of `flick-gap8` shows `cancelable=0` from the first reopen move). The discrimination is Lean
  (`old_rule_differs`, the `passive-reopen` rows) and the driver test, not the replay.

## Why defaultPrevented (identity over inference)

- DOM: `preventDefault()` runs "set the canceled flag"; the flag is set only if `cancelable` is true and the event's in-passive-listener
  flag is unset; `defaultPrevented` returns the flag (https://dom.spec.whatwg.org/#dom-event-preventdefault, #set-the-canceled-flag).
- WebKit: `Event::setCanceledFlagIfPossible` sets `m_wasCanceled` only if `m_cancelable && !m_isExecutingPassiveEventListener`
  (`Source/WebCore/dom/Event.h:218-224@862f17d`); `defaultPrevented()` returns it (`Event.h:122@862f17d`).
- Chromium: `Event::preventDefault` returns early (with a console error for `kPassive`) while handling a passive listener, and sets
  `default_prevented_` only if `cancelable_` (`third_party/blink/renderer/core/dom/events/event.cc:243-260@f842f52`).
- So `cancelable && out.prevent` is a prediction and `defaultPrevented` is the fact. The fact also covers a second listener that
  already prevented the move (the hub serves several clients): then the page does not scroll natively and holding is right.

## The model (Lean `Fw.Parts.ComboScroll`)

`Dlv` has three input bits per move: `cancelable`, `passive` (the listener running is passive) and `other` (an earlier listener
prevented). `Dlv.prevented d o = d.other || (o.prevent && d.cancelable && !d.passive)` is the DOM rule; `holds o d` is that bit
and `wstep` takes it where it took the cancelable bit. `MorphEnd.step` is unchanged.

| Statement | Theorem |
| --- | --- |
| release off: wrapper equals the inner reducer | `wstep_off`, `faithful_w` |
| decisions (`prevent`, `goal`, `flip`, core state) are the inner reducer's | `wstep_prevent`, `wstep_goal`, `wstep_flip`, `wtrace_decisions` |
| a write needs `held` | `fix_write_held` |
| no script write against a native scroll after an unheld move, at any frame rate | `native_quiet`, `cadence_w` |
| a passive move is unheld, and then every frame is quiet | `holds_passive`, `passive_quiet` |
| arm-late's passive listener: `holds` equals `holds` of the honored output; where its invariants hold the bit is the old one | `holds_arm`, `arm_late_holds` (with `MorphMountArmLate.honorOut_of`) |
| arm-late passive outside the band: unheld, quiet | `arm_passive_unheld`, `arm_passive_quiet` |
| the old rule was wrong for a passive listener | `old_rule_differs` |
| bricks keep their theorems with the wrapper | `wclamp_le`, `wrelease_quiet`, `wrelease_close_free`, `wrelease_starts`, `wrelease_rel` |
| no accepted pick has release:on with waapi or waapi-scoped | `decided_no_release_waapi`, `accepted_no_release_waapi`, `finish_refuses` (`ComboScroll`) |

Witnesses (`#guard`): `passiveTrace` (the user's trace with a cancelable passive reopen) writes nothing in the wrapper and 4900
twice in the inner reducer; `otherTrace` holds when an earlier listener prevented.

## TS twin

`end.logic.ts`: `moveStep` is the decision only; `prevented(out, delivery)` is the DOM rule (used by `step` for the golden);
`hold(h, next, dp, scrollY)` sets `held := dp` and re-pins at the scroll position when the bit returns, only with release on.
`driver.ts` `move` calls `preventDefault()` when the step prevents and the event is cancelable (the guard avoids Chromium's
"Ignored attempt to cancel" message), then passes `e.defaultPrevented` to `hold`. `WheelLike` and `TouchLike` require
`defaultPrevented`. The reducer `step` is the model twin of the golden; the driver is the identity.

## Look class

Unchanged from the scroll-fight note: with release on, a reopen the browser does not let the page cancel leaves the page to the
finger. The new part: a passive listener is now treated the same way (it used to pin against the scroll).

## Accepted limits and follow-ups

- CI Chromium replay stands in for the phone (Playwright WebKit cannot drive a touch drag); the phone re-check is the user's step.
- The replay does not discriminate old from new (above). Follow-up: a profile whose reopen touch starts after the fling stopped, near the
  platform, would; the page has scrolled away by then in the scripted paths.
- The `+allpassive` arms (named `+passive` in run 40142598495, renamed after) are a harness model: `combo-replay.mjs` `PASSIVE_JS` forces `passive: true` on every `touchmove` and `wheel`
  listener and adds one blocking no-op `touchmove` listener so Chromium keeps the event cancelable. The real cases are the band hub
  and arm-late's mount listener on the phone (INFERRED, not measured there).
- The toolbar-resize fight near y 1859 is out of scope.
- `combo-metrics.mjs` verdicts are a TS stand-in (not Lean). New: `nativeWrites` counts a write whose latest preceding touchmove was
  not default-prevented (the recorder reads `defaultPrevented` in a document listener after the page's capture handler).

## Re-run

- Push to `ci/device-replay` with `[ci:device-replay]` in the message. `combo` builds this commit and `BEFORE` (set in the
  workflow to `13f319e2a`), replays the `delta` arms (user, release and their `+passive`) on `before` and the bisect set on `after`;
  artifacts `combo-<leg>`. Summaries: `combo-cli.mjs summary --in <leg>/<build>/run.json` (new last column: writes against a native
  scroll).
- Runs of this task: device-replay 40142598495 (success), lean 40142598556 (success); one push of three used.
