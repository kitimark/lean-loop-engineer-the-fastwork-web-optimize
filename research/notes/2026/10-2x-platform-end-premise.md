---
id: 2026-10-2x-platform-end-premise
kind: note
title: "platform-end-premise: fastwork.com also ends at the platform card; WebKit fires media-query change events inside Page::updateRendering"
status: draft
created: 2026-10-22
topics: [platform, end-of-page, snapshot, webkit, media-queries, rendering-update]
---

# platform-end-premise

Task platform-end-premise. Question: the platform:mq result (ledger row n=42) rests on two premises. (1) Does the
original fastwork.com page end at the platform card at phone width (390-430) and desktop width (1280)? (2) Where does
WebKit run media-query change listeners inside `Page::updateRendering` (premise P1 of
`research/notes/2026/10-2x-platform-shrink-mq.md`)?

Sources: snapshot `snapshot/site` at commit 94928077 (unmodified, byte offsets below are into the minified files);
WebKit pinned clone `.cache/upstream/WebKit@862f17d` (sha 862f17dcae0aace47ea0ec16e209d960abfd553c,
`refs/upstream/sources.lock.yaml:26-30`). No measurement (accepted limit).

## Answer 1: yes, the original ends at the platform card at every width (CONFIRMED by source)

Nothing in flow follows the card at 390-430 or at 1280. The page order is the same at every width, and the card's bottom
is the bottom of the page.

| fact | source (CONFIRMED) |
|---|---|
| Page template: `<div class="start-selling"><!> <main><!> <!> <!> <!> <!></main></div> <!>`. The slot before `main` is the nav, the five in `main` are hero, people, pain, commission, platform, and the slot after the div is the waitlist dialog | `_app/immutable/nodes/2.DyWL8TcE.js` byte 364269 (`vN=h(`), mount code 364269-364900: platform `GM(V(_,2),{})` at 364831 is the last child of `main`, dialog `gN(V(c,2),...)` at 364855 |
| No width condition: the five sections mount without an `if` block (no `m(...)` around them) | same, 364269-364900 |
| The root layout renders only `children`, with no footer | `nodes/0.Z5L-ui-T.js` bytes 10348 and 11572; `nodes/1.DmlURg7t.js` is the error page |
| The prerendered HTML has the same order: `<section id="platform" ...>` at 69185, `</section>` 93894, `</main>` 93911, then the `<dialog>`, the boot `<script>`, an empty `<div id="tooltip-portal-exit">` (no CSS rule) and `<nav class="site-locale-links">` at 99466, which is visually hidden (`position:absolute`, 1px, `clip-path:inset(50%)`, index.html byte 3999) and adds no scroll height. No `<footer>` in the file | `index.html` bytes 69185, 93894, 93911, 99466, 3999 (`grep -c '<footer'` = 0) |
| The closed dialog is out of flow: `display:none; position:fixed`, shown only when `[open]` | `assets/DialogHeader.Qcgwm6ST.css` bytes 16223 (base rule) and 16600 (`[open]` rule) |
| The section's only child is the card (`<section id="platform"><div class="start-selling-platform-card">...</div></section>`) | `nodes/2.DyWL8TcE.js` byte 343776 (`WM=h(`) |
| The section's padding is 0 at every width: the shrink-track rule (two classes) overrides the one-class `padding:0 56px 80px`, and the `width<=720px` band repeats `padding:0` for it | `assets/2.gBuqKVzi.css` bytes 94996 (desktop rule) and 144953 (inside `@media (width<=720px)` at 144884) |
| The section only ever has the classes `start-selling-platform is-platform-shrink-track is-visible` plus the `is-platform-shrinking` toggle. The `is-platform-pain-underlay` rules (negative `margin-top`) never apply because no JS or HTML sets that class | `nodes/2.DyWL8TcE.js` byte 347345; `grep is-platform-pain-underlay` finds nothing in the JS or `index.html` |
| The card has `overflow:clip` and no margin, so nothing below it adds scroll height | `assets/2.gBuqKVzi.css` byte 95357 |
| `body` margin is 0, `.start-selling` and `main` have no bottom padding | `assets/0.ChGpbVhU.css` byte 26818; `assets/2.gBuqKVzi.css` bytes 227058, 227610 |

So the original's shrink callback reads the same geometry as the rewrite's. The callback is at `nodes/2.DyWL8TcE.js`
byte 344454; `r=innerHeight*.85` is at 344562 and the shrink is 0 while `bottom >= 0.85*innerHeight`. With a plain
scroll, the card bottom at the page end equals the document bottom, which is at or below the viewport bottom. The
shrink stays 0, and on the phone the original's write is dead code too (as on desktop). Lean `unshrunk_run` applies
to both pages unchanged. The premise "the platform card is the last section" holds for the original. No port task is
needed; nothing is missing below the card.

Limit (INFERRED, not checked): a rubber-band overscroll past the page end can move the card's client rect above
`innerHeight` for a moment, and on iOS `scrollY` can exceed its maximum while the page bounces. If the pull exceeds
15 % of the viewport, the original computes a nonzero shrink. On the phone that changes nothing visible: the
`(width<=860px)` band pins the look (`assets/2.gBuqKVzi.css` byte 208846), and the white section background hides
behind the card because the padding is 0. On desktop with a trackpad bounce the card could scale for a moment. This
is a follow-up, not part of the unit.

## Answer 2: WebKit runs media-query change listeners in the MediaQueryEvaluation step (CONFIRMED by source)

All file:line references below are at WebKit 862f17dcae0aace47ea0ec16e209d960abfd553c, under `Source/WebCore/`.

| step | file:line |
|---|---|
| `Page::updateRendering()` | `page/Page.cpp:2231` |
| Resize steps, then scroll steps | `page/Page.cpp:2290-2296` |
| **MediaQueryEvaluation step: `document.evaluateMediaQueriesAndReportChanges()`** | **`page/Page.cpp:2298-2300`** |
| which calls `m_mediaQueryMatcher->evaluateAll(EventMode::DispatchNow)` | `dom/Document.cpp:5861-5867` |
| `evaluateAll` re-evaluates each live `MediaQueryList` | `css/MediaQueryMatcher.cpp:95-116` (call at 111) |
| `MediaQueryList::evaluate` dispatches `change` (`MediaQueryListEvent`) synchronously, so the JS listener runs here | `css/MediaQueryList.cpp:93-110` (dispatch at 108) |
| later steps of the same update: web animations, `requestAnimationFrame` callbacks | `page/Page.cpp:2307-2309`, `2329-2331` |
| layout, then layout with compositing-layer update, before the update ends | `page/Page.cpp:2337`, `2399` |
| environment changes (appearance, accessibility, style environment) schedule this step | `page/Page.cpp:1098`, `4274`; `dom/Document.cpp:10038` |

The platform:mq handler calls `frame()` synchronously from the `change` listener
(`apps/site/src/parts/platform/index.tsx:107-108`). Its `--platform-shrink` write therefore runs inside the
MediaQueryEvaluation step, before the update's layout (Page.cpp:2337) and compositing flush (2399), so it lands in
the frame being produced. P1 holds in WebKit. The width change itself is visible to that step because the resize
steps (2290-2292) run first in the same update. Chromium was not checked; P1 as written in the note covers WebKit
only.

## What this changes in the plan

- Ledger row n=42 (`research/findings/ledger.json`, lead edit): replace the open premise "whether the original snapshot
  also ends there is open" with "CONFIRMED: the original also ends at the platform card at every width (this note)".
  Extend the lesson: the original's shrink is dead code on a plain scroll at phone and desktop width alike, so
  platform:mq cannot win on any end-of-page window. Next: no port task. Re-open only if the snapshot changes.
- Note `10-2x-platform-shrink-mq.md` premise P1: cite `Page.cpp:2298-2300@862f17d` and `MediaQueryList.cpp:108`
  instead of "the spec text".
- Follow-up (not in this unit): rubber-band overscroll at the page end (iOS `scrollY` past the maximum, macOS trackpad
  bounce) is the only path where the original computes a nonzero shrink; it is unmeasured.
