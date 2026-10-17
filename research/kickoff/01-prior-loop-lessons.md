# 01. What v1 teaches v2: lessons from the first loop

2026-10-17. Kickoff research for the v2 loop-engineering experiment (React rewrite, engine-math measurement, Lean
proofs, feature-flagged parts, agent teams). Input for the plan architect.

**Scope.** This note reads the v1 repo (`../fastwork-com-web-optimize`, read-only, written `v1:`
below) and its local stores. It copies no Fastwork code, assets or personal data. Page elements are described in words,
and the v1 file that holds the detail is cited.

**Status words.**
- **CONFIRMED**: a v1 document, a v1 data store or an engine source citation inside v1 says so, and the path is given.
  Engine facts carry v1's own status from its verifier table (`v1:research/knowledge-distillation/README.md` §6).
- **COUNTED**: I counted it on 2026-10-17 from the v1 files or stores. The method is given.
- **ESTIMATE**: derived, with the method given.
- **INFERRED**: my reading or recommendation for v2. It has not been checked.

---

## 0. Summary for the plan architect

1. **v1 worked, but it cost a lot.** On the iPhone, slow frames (>34 ms) in the user's own swipe fell from 20.1 % to
   1.7 %. At the end of the page, the longest frame fell from 584 ms to 42 ms. It took 10 days, 442 agents, 2,483
   commits and about $13,500 at API list prices (CONFIRMED, `v1:research/loop-distillation/README.md` §5).
2. **Most of the engineering went into the loop, not the page.** v1 has 43k lines of tools and 54k lines of tests
   (COUNTED). 231 of 276 incidents were bugs in its own tools (COUNTED, `v1:console/incidents.json`). The rulebook grew
   to 9.7k words, and every agent re-read it on every turn.
3. **All three of the user's pain points show up in v1's own data.**
   - **Device dependency.** About 111 of 276 incidents involve the iPhone or Simulator driver (USB, WDA, inspector,
     heat).
   - **Compiled-source patching.** The 24 h retrospective names "patching a frozen, minified bundle limits the size of
     each fix" as cause C6. It also proposes the redesign the user now wants, and no one tested it.
   - **Coupling and test cost.**
     - A full `npm test` took 250-280 s, and up to 480 s in the shared lane.
     - Any tooling commit ran the whole suite until 13 Oct.
     - `lib/lock.mjs` grew from 291 to 1,685 lines.
     - The refactor plan's first package (a shared CLI parser and a tools map) never landed. Copies of the argument
       parser grew from 8 to about 24 files.
4. **The seed backlog for v2 is clear.** The 30 lessons sort into six groups: per-frame script, properties the
   compositor cannot run, WebKit-only layout traps, layer and blur pricing, work nobody sees, and scroll-jacking. Each
   group maps to elements of the page that v2 can put behind a flag and test one at a time (§A.1).
5. **Engine math is a good idea, with one limit.** v1 found that engine source tells you which stage runs, never how
   many milliseconds it costs. Of the WebKit costs v1 found, 13 of 30 lessons had no tool coverage, and several depend
   on the value at frame N, not on the stylesheet. Counts predicted the phone wrongly in the same direction five times
   (layer builds at first open). An engine-math model needs a validity table against the device, with a small device
   budget kept (§A.4).
6. **Keep the method.**
   - A frozen, pinned baseline.
   - One measurement lock with a quiet-host gate.
   - An A/A noise floor, verdicts from disjoint ranges over at least 3 runs, and ±4 ms "twin" thresholds.
   - Prediction cards before data.
   - OBSERVED/CONFIRMED status on platform claims, and reading the engine source first.
   - Memory notes with Rule/Why/How.
   - "Every rule has an enforcer, or it is labelled a convention."
   - The less-work landing rule.
   - Pixel-tolerance tiers.
   - Proposals with Try-it pages, and blind swipe A/Bs.
7. **Drop the growth pattern.**
   - Rules were added per incident and rarely removed.
   - Agents wrote board state that events already knew.
   - The lead acted as router.
   - 160 agents ran in the first 29 h.
   - Timing-dependent tests used real sleeps.
   - Modules ran side effects at import.
   - Helpers were duplicated with different meanings.
   - Many JSON stores were written by many writers, with no event log.
8. **Cost was mostly context, not thinking.**
   - Cache reads were 96 % of tokens, and Opus was 97 % of weighted usage (COUNTED from `usage.jsonl`).
   - Fix owners took about 33 % and the lead about 20 %.
   - Recurring "check" prompts re-read the lead's long context about 490 times, for about 200 M tokens.
   - A cheaper team (Sonnet and Haiku for lookups, routing and stewarding) came only on day 5.
9. **For Lean, INFERRED:** the bug-prone parts of v1 are small, pure state machines buried in IO code:
   - lock queue policy;
   - A/B verdict;
   - frame counting with twins;
   - incident dedup;
   - thread routing;
   - status derived from events;
   - proposal lifecycle;
   - scrub rules.

   These are where Lean specs and proofs pay off. The IO shell stays thin and tested by examples (§B.5).
10. **Facts about agent teams that v1 learned the hard way** (§C.3):
    - Teammates ignore a definition's `effort` and `isolation`.
    - A teammate cannot spawn teammates.
    - `EnterWorktree` inside a team switches the whole session (I-272).
    - Idle teammates are not woken by their own background-task notices (I-274).

---

## 1. v1 in numbers

| What | Value | Status / source |
|---|---|---|
| Duration | 30 Sep to 9 Oct to the "done" build (g0.0m); release work to 13 Oct | CONFIRMED, `v1:research/loop-distillation/README.md` §5 |
| Commits on `main` | 2,521 today (2,483 on 12 Oct); 0 merge commits | COUNTED, `git log --oneline \| wc -l` |
| Largest commit prefixes | `ops` 505, `tools` 290, `fixes` 120, `research` 66, `docs` 60 | COUNTED, `git log --format=%s` prefix histogram |
| Day-1 split | process 38 %, research 22 %, tooling 20 %, fix deliverables 19 % | CONFIRMED, `v1:research/loop-distillation/README.md` §5 |
| Tools | 146 files, 43,122 lines (`tools/`, 113 entries in `tools/lib/`) | COUNTED, `find tools -name '*.mjs' -o -name '*.js' \| xargs cat \| wc -l` |
| Tests | 268 files, 54,506 lines; 2,525 tests; full `npm test` ~250-280 s wall | COUNTED (files); CONFIRMED (tests, time), `v1:CLAUDE.md` "Tooling is guarded by tests" |
| Incidents | 276: tool 231, env 42, fix 2, research 1; 233 resolved; 34 blocking; median time to resolve 1.1 h, p90 3.9 h | COUNTED, `v1:console/incidents.json` (the 12 Oct write-up says 266/224) |
| Findings | 375 (measurement 146, pitfall 123, coupling 56, technique 42) | CONFIRMED, loop-distillation §5 |
| User console | 556 thread files (T-), 332 step files (C-), 82 proposal files (41 proposals) | COUNTED, `ls v1:console/{threads,steps,proposals}` |
| Fix topics | 151 directories; 49 with a `results.json` | CONFIRMED, loop-distillation §5 |
| Rulebook | `CLAUDE.md` 9,692 words (1,289 at the first commit), 95 commits changed it | COUNTED (`wc -w`); CONFIRMED (history), loop-distillation §6.2 |
| Memory notes | 38 notes | COUNTED, `ls v1:memory` |
| Design docs | ~282k words in `fixes/*.md` and `research/architecture/*.md` | CONFIRMED, loop-distillation §5 |
| Cost | $8,576 read once on 5 Oct (Opus $8,342, Sonnet $214, Haiku $20); ~$13,500 for the whole project | CONFIRMED as an article figure and an ESTIMATE, `v1:research/team-article/artifacts/building-an-ai-loop-from-scratch.html` "What it cost" |

---

## A. Technical performance lessons: the seed backlog for v2

### A.1 Elements that caused jank, the fix that won, and the v2 experiment flag

Rows follow the lesson numbers in `v1:research/knowledge-distillation/README.md` (written "KD L<n>" below). Element
descriptions are mine. The original code lives at the cited lines of `v1:site-pretty/_app/immutable/nodes/2.*.js` and
`.../assets/2.*.css` (not copied here). The flag name in the last column is the INFERRED proposal for v2.

| # | Page element (described) | Mechanism | Engine where it bites | v1 pattern that won (CONFIRMED by the fix README) | v1 effect (OBSERVED in v1) | v2 flag / experiment (INFERRED) |
|---|---|---|---|---|---|---|
| 1 | Shared scroll engine: one rAF that runs every effect's callback | Read-write-read forces sync style and layout. A nav hit test writes inherited `pointer-events` around `elementFromPoint` | Both. On WebKit, reading `scrollY` runs pending layout (CONFIRMED, `LocalDOMWindow.cpp` 1508-1512) | `elementsFromPoint` skipping its own subtree; cached MQL and querySelector results; write on change only; skip reads whose answer cannot show (hit-skip) | Chrome 6x: the nav callback cost 526-617 ms per run before. Simulator layouts 656 → 621 from hit-skip alone | `scroll.engine = original \| batched \| observers`; `nav.hitTest = probe \| elementsFromPoint \| io` |
| 2 | Hero exit: a 200vh track with a sticky hero; one inherited custom property drives opacity, translate and blur of ~230 elements | An unregistered inherited var write restyles the whole subtree every frame | Both (modelled 5-12 ms per frame) | Card fade moved to a compositor scroll-driven animation (`fixes/hero-exit-threaded`, v6) | The user preferred v6 in both blind swipes. Medians 31 → 18 → 7 slow frames (original, v4, v6); v6 vs v4 threshold-sensitive | `hero.exitDriver = cssVarJs \| viewTimeline \| waapi` |
| 3 | "Shrink" effects on cards that phone CSS has already disabled; an orbit on a `display:none` element | JS keeps easing and reading rects for effects CSS turned off | Both | Gate JS on exactly the CSS media query, re-run on MQL `change`; delete instead of hiding | Chrome 6x 66.5 → 71.6 fps; phone frames >20 ms 60-64 → 40-43 | `cards.shrink = always \| mqGated \| removed` |
| 4 | A future card with a JS-eased var and a 0.9 s `transform` transition at the same time | Two drivers on one property; a mid-scale `transform-origin` flip | Both (CSS Transitions spec, CONFIRMED) | One driver per property; `transition: none` where script writes | Card jumped up to 270.9 px (Chrome probe) | `card.doubleDrive = on \| off` |
| 5 | The "o" in the People title opens into a row of faces; avatar exit; accent-word width | `grid-template-columns`, `width`, `max-width`, `margin`, `flex-basis` animated | Both (layout) | FLIP without reads: set the final size, slide with transform via WAAPI, Δ from stylesheet em values | Chrome layouts 56 → 4; Simulator 30 → 8 (PR-031, a proposal because sub-pixel frames differ) | `people.titleOpen = layoutAnim \| flip` |
| 6 | Hand-drawn SVG accent word (stroke redraw every ~3 s plus a `step-end` "boil"); gradient sweeps on `background-clip:text` titles; SMIL glint | `stroke-dashoffset` is an SVG layout change in WebKit (CONFIRMED, `StyleDifference.cpp`); `background-position` repaints; `steps()`/`linear()` with points stay on the main thread on iOS 26 (CONFIRMED for 26.x) | WebKit worst; Chrome cannot composite dashoffset either (CONFIRMED, `compositor_animations.cc`) | Boil `step-end` → a keyword-`linear` ramp with byte-identical frames; sweep → a gradient band on `::after` moved by `translateX` (PR-009) | Bottom of the page at "idle": 240 style passes and ~481 paints per 4 s → 8 and ~33 | `accent.mode = dashoffset \| frames \| video`; `titles.sweep = bgPosition \| translateBand \| off` |
| 7 | Typing and count-up text inside nested size containers (six levels under the platform section) | A restyle under a size container runs an interleaved layout inside style recalc (CONFIRMED WebKit; "whole view" WEAKENED) | WebKit | Reveal in chunks (two characters per step), fixed-size box; no `container-type` above per-frame text | Chrome 1x layouts 226 → 97 | `typing.step = char \| chunk \| clip`; `platform.containers = on \| off` |
| 8 | Avatar pill (104x32) that rotates every ~1 s by swapping a branch and mounting fresh images | Presence flips (opacity reaching exactly 1, transform/filter none ↔ some) force layout in WebKit (CONFIRMED, `StyleDifference.cpp`); Blink does not | **WebKit only** | Keep slots mounted; rest values never flip (`opacity: 0.999`, `scale(1)`) | Phone: whole-view layout after 71/71 slides → 1/36; slow frames at rest 19-27 → 0 | `avatars.rotator = remount \| keepMounted \| restOffFlip` |
| 9 | Profile deck of six phone-mock cards (`aspect-ratio`, `height:auto`) next to sticky sections while the iOS toolbar slides | Each toolbar step is a new layout viewport and marks fixed/sticky renderers dirty (CONFIRMED, `LocalFrameView.cpp`); the link into the shells is UNRESOLVED | **iOS Safari with a finger only**; Chrome emulation has no toolbar | Definite size from a width formula (`calc(100cqi*764/353)` on an inline-size container) | Phone, finger y 1000-3400: layouts ≥5 ms 152-159 → 0-1; slow frames 12-18 → 2-6 (g0.0j) | `deck.sizing = aspectRatio \| cqiFormula` |
| 10 | Per-section pause rule `:where(*) {animation-play-state: paused !important}` and `content-visibility` gates on an observer with a 100 % rootMargin | Each flip invalidates a subtree; deferral changes the size and flaps the observer (800 flips per 10 s) | Both; the largest style record on the phone (29-32 ms) | Pause the animated element, not the section; hysteresis and idle pre-warm; count the gate's own writes | ~10 of the phone's 14-17 slow frames per run sat on ~8 such flips | `scene.pause = section \| element`; `scene.defer = flap \| hysteresis \| off` |
| 11 | End-of-page morph: the nav pill tweens into a full-screen menu over 680 ms (size, top, radius, `color-mix`, animated backdrop blur) | Resizing a non-tiled composited layer discards its backing store (CONFIRMED, `RemoteLayerBackingStore.mm`); one inherited `--morph` var; plus 3-4 more terms of 3-10 ms each | WebKit, heavily; Chrome 6x showed 110 fps | compositor-morph (PR-030): transforms on a scroll timeline, rounded box from four corner clippers; later a steady 20 px glass (g0.0k) | Phone paint per morph frame 0.28-0.29x; end-of-page longest frame 584 → 42 ms | `endMorph = original \| compositor \| fingerFollow`; `glass = animatedBlur \| constant` |
| 12 | Rolling countdown digits: 10 `will-change` faces per digit, ~80 face layers per clock, plus a copy in the hidden menu | Layer count multiplies paint, at about 0.14 ms per repainted layer (derived) | WebKit | One strip per digit (48 → 16 layers); isolate the small ticking clock from the big menu layer | Re-entry paint 53.5 → 21; menu-centre redraws per open 196 → 11 | `countdown.layers = perFace \| strip`; `menuClock.ownLayer = on \| off` |
| 13 | Menu layers created in the first frame of the open | WebKit keeps no layer pool (CONFIRMED for detach) | WebKit; invisible to Chrome and Simulator counts | Build layers at a still moment near the end (v14); later two flat GPU layers plus a clip | First open 28.5 → 26.5 ms (+10.6 MB), then ~11 MB less (g0.0f) | `menu.layerWarmup = onOpen \| nearEnd` |
| 14 | One scroll threshold (hero progress 0.72) with three owners: People reveal (blur 14 px → 0 over 1.6 s), dark theme flip, nav pill change | The hidden card's layers have no backing store, so they allocate and paint in the flip frame | WebKit (58.2 ms and 43.3 ms frames) | Cut the blur's invisible tail; skip the fade after a fast flick (PR-041); keep the card pre-painted at opacity 0 on touch (g0.0m) | Reveal frame on a flick: median 50 → 30.5 ms, for +22 MB graphics memory | `people.reveal = blurFade \| shortTail \| instantOnFlick \| prePainted` |
| 15 | Screen-tall card blur, entry keyframes left on `blur(0)` | Blur on a viewport-sized layer; Chrome never composites blur animations (CONFIRMED, reason 4096) | Both, differently | Cut the tail. Do not retime the blur to `cubic-bezier` for Core Animation: that doubled Composite | Phone paint area 53.6-54.7 → 48.1-49.2 Mpx per run; the cubic retime made the reveal frame 42 → 74 ms | `blur.tail = full \| trimmed`; never a "GPU blur" arm without memory counts |
| 16 | End stages and the menu photo wall: five 1282x1282 PNGs in ~138 px columns under grain and blend, no `srcset` (~33 MB decoded) | Paint of large backing stores; Chrome paint counts are blind to it | WebKit | Ablation showed the cost (slow frames median 16 → 3 with backgrounds off); smaller files alone did not buy frames | Not shipped; left as a user proposal | `endBg.images = original \| dprSized \| flattened \| off(ablation)` |
| 17 | Stacked filters, clips and backdrop blur | Engine-specific artefacts (WebKit bug 312584, grey corners) | Both | One clip rule; capture Chrome with screencast, not `captureScreenshot` | Visual only | Visual-regression arms per engine |
| 18 | Infinite loops: countdowns off screen and in the hidden menu, the hero under the opaque People card, sweeps/glint/vinyl at the bottom | Work at rest: 1,816 elements restyled per second mid-page | Both, plus heat | Pause via an observer per element plus covered and faded states; `getAnimations()` pause resumes from held time | Simulator at the People title: 65 → 2 layouts, 74 → 0 paints, pixels identical; heat slope lower | `idle.pausePolicy = none \| perElement`; a "rest probe" test at every scroll position |
| 19 | 1 s countdown on `setInterval` | Under thermal mitigation WebKit aligns repeating timers to a 30 ms grid and re-arms from the actual fire time (CONFIRMED on WK main; iOS 26 UNRESOLVED) | WebKit hot | Derive the displayed time from the clock | One second skipped about every 50 s at Serious | `countdown.timer = interval \| clockAligned` |
| 20 | Third-party analytics scroll listener on `scrollend` | 59-76 ms task per scroll in Chrome 6x | Both | Only the owner's analytics switch removes it | Deferring it moved the task to idle in 3 of 5 runs | `vendors = on \| off` (the rewrite should ship none by default) |
| 21 | Scroll-jacked ending: non-passive capture `wheel`/`touchmove` listeners, `preventDefault`, `scrollTo(... 'instant')`, and the panel mounted in the scroll frame | Hijack plus a 42-75 ms mount in a scroll frame | Felt only with a finger | Native scroll, or a finger-following compositor interaction; never mount in a scroll frame | ~349 fix commits on that line; a rollback (g0.0b) and a return (g0.0k) | `end.interaction = hijackTween \| fingerFollow \| nativeRunway` (a design decision per arm) |
| 22 | Where a stall lands in an eased motion | Perception: a stall in the slow landing is tolerated better than in the fast start (8/8 forced choices, one user) | Perception | Keep layer builds, mounts and decodes out of the fast start | Direction, not a calibration | Design rule for every flag arm |

Sources for every row: `v1:research/knowledge-distillation/README.md` §3 (lessons 1-22) and the `fixes/<topic>/README.md`
files it cites. Best-build ladder: `v1:fixes/BEST_BUILDS.md`.

### A.2 Fix patterns that won, by engine

CONFIRMED as v1 practice (`v1:research/architecture/gpu-compositor-playbook.md` §3 and §7, KD §5):

- **Compositor-only motion.** Animate only `transform`, `translate`, `scale`, `rotate`, `opacity`, and `filter` /
  `backdrop-filter` with care. Drive scroll-linked motion with `scroll()`/`view()` timelines and time-linked motion
  with CSS or `animate()` using keyword or `cubic-bezier` easing. No `var()` in keyframes, and no `steps()` or
  `linear()` points on iOS 26.
- **One value function.** One function `f(progress, geometry)` produces the keyframes, the inline values for the first
  frame, and the state buckets. Geometry comes from a ResizeObserver size box and is never read in a moving frame.
- **Layers on a budget.** Create layers at load or at a still moment. Never resize them in motion. Release them at
  rest. Write the MB down.
- **Rest states off the WebKit flip.** Use `0.999` and `scale(1)`. Keep elements mounted.
- **No per-frame reads.** Use observers. Do all reads before all writes, once per frame.
- **Pause per element**, with visibility, covered and faded owners.
- **Definite sizes next to sticky/fixed elements.** In WebKit only layout **plus** size containment makes a layout
  boundary (CONFIRMED, `RenderObject.cpp`).
- **Less-work fixes** land on counts plus a short phone no-worse check.

What did not work (CONFIRMED by v1 fix READMEs; KD lessons 1, 2, 6, 11, 15, 16):

- Removing one reader moved forced layout to the next reader.
- A `view-timeline` hero won at y≈50 and lost at y≈700 on the phone.
- Registering `--morph` with `inherits:false` left children stale on WebKit.
- Blur removals scored by rAF gaps.
- The `cubic-bezier` blur doubled Composite.
- Smaller image files did not buy frames.
- Bundling fixes per build.
- Replacing the accent word alone: 0 slow frames on a test page, 4-8 per run on the full page.

### A.3 Chrome vs Safari: where Chrome is blind

| Cost | Chrome sees it? | WebKit / iPhone | Source (v1) |
|---|---|---|---|
| Main-thread script, style, layout | Yes. The 6x throttle slows only the renderer main thread (CONFIRMED) and is super-linear for DOM work (6x costs 7.8x) | Yes | `research/cpu-throttle-calibration/README.md`, KD L23 |
| Presence-flip layouts (opacity 1, none ↔ some) | **No** (Blink does not relayout) | Yes | KD L8, fact 4 |
| `steps()`/`linear()` points off the compositor | No (no timing exclusion in Blink) | Yes on iOS 26.x | KD fact 5; `tooling-landscape` §5 rule 10 |
| Backing store discarded on layer resize | Not modelled (cc raster differs) | Yes | KD fact 16 |
| Layer build at an interaction's first frame | No | Yes, 6.5-11 ms | KD L13 |
| Raster, blur, GPU, render-server time | No (throttle is main-thread only) | Only Instruments sees render-server time; rAF does not | `measurement-protocol-v2.md` L13; `safari-inspector-probing.md` §0.5 |
| Toolbar resize with sticky elements | No (no toolbar in emulation) | Yes, finger only | KD L9 |
| Size-container interleaved layout | Different | Yes | KD L7, fact 18 |
| Timer drift when hot | No drift | Yes | KD L19 |

Calibration facts (CONFIRMED in v1):
- iPhone raw CPU ≈ Chrome 1x on the M1 Pro Mac (microbench 261 vs 255 ms).
- Scripted-scroll jank counts best match Chrome at 6x (12.3 vs 15.7 slow frames per run). It reproduces counts, not
  causes.
- Chrome 1x mobile emulation showed 0.0 slow frames per scroll, against 15.7 on the phone.
- In v1's setup the Simulator was unusable for A/B direction: one comparison reversed with disjoint ranges. It was fine
  for counts and function.

Source: `v1:research/cpu-throttle-calibration/README.md`, `v1:research/simulator/README.md`, KD L23.

### A.4 What this means for "measure from engine math instead of the device" (pain point 1)

- **What v1 already proved can be read from source.** There are 16 WebKit cost rules with file:line, and 14 of them have
  a form a linter can see (`v1:research/tooling-landscape/README.md` §5). They are good seed axioms for a v2 cost model
  and for the WebKit rule pack v1 recommended but never built.
- **What source cannot give: milliseconds.**
  - "No WebKit rule here gives a cost in ms. The source says which stage runs, not how long it takes" (tooling-landscape
    §5).
  - Rules 1-3 are value conditions at frame N, and rules 12-13 are runtime only (sizes, composited state).
  - v1 judged a static per-property ms table "not worth building" because it would give false confidence
    (tooling-landscape §6, Build 3).
- **v1's derived constants are a starting point, not truth.**
  - A budget for this phone at 60 Hz: ~8-12 ms of variable main-thread work per frame, ~120-300 restyled elements,
    ~1.5 Mpx painted, ~10 MB of new backing.
  - ~0.14 ms per repainted layer.
  - 0.72 ms per frame of WebKit restyle for active scroll-driven targets.
  - All are ESTIMATES in v1 (`research/design-engineering/apple-math.md`, cited in KD L12, L30 and §3 traps).
- **Proxies failed in a systematic way.**
  - Count-based predictions for first-open layer builds missed in the same direction five times (KD L13, M6).
  - A model predicted a 30-45 ms gain that measured 6-9 ms (`measurement-protocol-v2.md` L1).
  - In blind swipes, Chrome and robot numbers disagreed with the user in 5 of 8 pairs. Only one metric agreed 7 of 7:
    frames over 50 ms per 100 moving frames, in the finger's zone, from the swiped run
    (`v1:research/architecture/stats-vs-finger.md`).
- **INFERRED for v2.** Treat the engine-math model as the **inner loop**: fast, deterministic, parallel. It ranks and
  screens candidates. The device stays the **outer loop** in a small, scheduled budget. v1's own 24 h retrospective
  asked for exactly this two-speed loop (C2) and found it was the biggest missed speed-up
  (`v1:research/management/lead-retrospective-24h.md` §3 C2, §5.1). Keep a running **validity table** per model output
  against the device's verdicts, as v1's `stats-vs-finger.md` did, and retire outputs that disagree.

### A.5 Risks specific to the React + MUI rewrite (INFERRED)

- **The rewrite is not the original's cost profile.** v1's costs came from how the Svelte page drives style:
  - inherited custom properties on large ancestors;
  - `:where(*)` pause rules;
  - Svelte `$state` flushes on fresh `[]` (KD L3 "Also");
  - JS-written vars every frame.

  A clean React rewrite may simply not have these costs, so "optimizing" it would prove nothing. **Recommendation:**
  every element gets an `original` flag arm that reproduces the original mechanism on purpose. The rewrite passes a
  **fidelity gate** first: per-zone slow-frame counts and per-event work counts in its `original` mode must fall within
  the original mirror's A/A spread. Only then are its experiments comparable.
- **React and MUI add their own per-frame costs.**
  - A React re-render per scroll frame is the analogue of the Svelte flush.
  - MUI's default styling engine (Emotion) injects styles at runtime, and a style-prop change per frame means new
    class rules.

  Animation-rate values should never go through React state or `sx`. Write them through refs, CSS variables on the
  consuming element, or WAAPI and scroll timelines. This is lesson 2 restated for React. Verify against the MUI and
  React docs before relying on it (claim status: UNRESOLVED here).
- **Pixel identity is the user's standing rule.** v1's user rejected a cheaper look-alike and asked for pixel
  identity or pre-rendered frames. Tolerance tiers T0/T1/T2 came later (PR-010 rev 3; `v1:memory/illusion-must-be-pixel-identical.md`).
  A rewrite must clear the same tiers against the frozen original before any perf claim, in Chrome and the Simulator,
  with screencast capture, frozen animations and A/A floors (KD L29).
- **Flags must not create the very costs v1 found.**
  - A flag check per frame, or a runtime toggle that flips a section attribute, re-creates KD L10: subtree
    invalidation and `will-change` flips at ±1 viewport.
  - Resolve flags at build time or at load, not per frame. Keep flipping one flag in a running page as a separate,
    named experiment.
  - For ablation arms, reuse v1's element-ablation fairness rules (`v1:research/element-ablation/README.md`): remove
    paint only, keep layout and motion, and run a C/V/C/V fairness check before any count.

---

## B. Process and architecture lessons

### B.1 Evidence for each of the user's pain points

**Pain point 1: the real device was needed for every measurement.**

| Evidence | Status |
|---|---|
| About 111 of 276 incidents touch the iPhone or Simulator driver (USB link loss, WDA automation-mode timeouts, inspector hangs, wrong web view, Critical heat readings, simulator leaks) | COUNTED, regex single-label over incident titles (`iphone\|phone\|wda\|usb\|simulator\|sim\|xcode\|thermal\|ioscap\|gesture\|inspector\|safari...`), an ESTIMATE ±10 |
| Phone blocks took 12-35 min plus 10 min cooling; one phone serialized everything; adding agents added queue length, not throughput | CONFIRMED, `v1:research/management/lead-retrospective-24h.md` C1 |
| I-042: WDA strokes collapsed to 50 ms flicks, so **every** robot-gesture run was void until fixed | CONFIRMED, retrospective C3; loop-distillation §6.1 |
| 19 end-of-page phone blocks: 5 pass, 6 fail, 5 open or insufficient, 2 attribution-only, 1 mixed | CONFIRMED, KD L28 |
| User minutes: steps to reload, re-tab or force-quit Safari 4 times in 26 min, before the root cause (a second inspector attached) was found | CONFIRMED, retrospective C3 |
| The timing deferral (`v1:memory/defer-timing-focus-call-tree.md`, 1 Oct) moved v1 to counts and call trees because of device and lock contention | CONFIRMED |

**Pain point 2: patching the compiled source was slow.**

| Evidence | Status |
|---|---|
| Retrospective cause C6: "Patching a frozen, minified third-party bundle limits the size of each fix". Conflict clusters, hand-resolved lines, and shared engines (scroll engine, morph, scene manager) touched by many topics | CONFIRMED, `lead-retrospective-24h.md` §3 C6 |
| The proposed structural redesign (native scroll timelines, per-element control, no inherited vars on large ancestors) was "UNRESOLVED; no one has tested this" | CONFIRMED, same section |
| A replace-all rename of a minified name broke six SVG circles, and three screenshots did not catch it | CONFIRMED, KD L3 (FINDINGS P1) |
| The overlay format could not carry binary files (I-067, I-209), and served stale immutable cache headers for overlay files (I-131) | COUNTED, `v1:console/incidents.json` |
| The end-of-page line cost ~349 fix commits, a rollback and a return | CONFIRMED, KD L21 |
| 151 fix directories for about 15 builds that landed | CONFIRMED (loop-distillation §5), with `v1:fixes/BEST_BUILDS.md` |

**Pain point 3: coupled, hard to read, slow to test, buggy.**

| Evidence | Status |
|---|---|
| Incidents by area (single label, from titles): device/driver ~111, flaky or timing-dependent tests ~47, console/threads/proposals/board ~42, lock/queue/lease ~39, measurement/A-B/bench ~10, release scrub ~9, serve/overlay ~4, guards ~4, host/disk ~3, other ~7 | COUNTED (ESTIMATE, regex) |
| Day 4 alone: 90 incidents and 116 threads | COUNTED (incidents by `openedAt` day); CONFIRMED (threads, loop-distillation §2) |
| 72 of the first 145 incidents (50 %) were coordination slips between agents, the user and devices. The largest class was lock jams (19). A stale board needing an agent to write it caused 8 | CONFIRMED, `v1:research/architecture/team-ops-plan.md` §1 |
| A full `npm test` grew to 250-280 s at ~1,640 tests and was capped at 480 s in the shared lane. Every commit touching tooling ran the **whole** suite through the pre-commit hook. A scoped run (release-only commits) arrived on 13 Oct (`3bf7e2ea`) | CONFIRMED, `v1:CLAUDE.md` "Tooling is guarded by tests"; `v1:package.json` |
| 290 `tools:` commits × ~4.5 min of full suite ≈ 22 h of serialized suite time, before re-runs from flakes | ESTIMATE (count × CLAUDE.md wall time) |
| `tools/lib/lock.mjs` grew from 291 lines (1 Oct) to 1,685 lines. About 32 tool modules and ~77 test files reference a `lock.mjs` module (the grep pattern also matches `*-lock.mjs`, so this is an upper bound) | CONFIRMED (291, `tools-refactor.md` App. A); COUNTED (1,685 and fan-in) |
| The refactor plan (`tools-refactor.md`, 1 Oct) found 8 copies of the argument parser and two `median`s that disagree on even n. Its package P1 (`lib/cli.mjs` plus `tools/README.md`) never landed: no `tools/README.md` exists, `lib/cli.mjs` is absent, and ~24 files still define their own `opt()` parser | CONFIRMED (plan); COUNTED (today) |
| Module-level side effects made files unimportable by unit tests (`fix.mjs` validated `--on` at import; `serve.mjs` ran with a top-level `await`) | CONFIRMED, `tools-refactor.md` §3 |
| Two process-tree modules with different jobs and nearly the same name (`lib/proc-tree.mjs`, `lib/proctree.mjs`) | COUNTED |
| The enforcer code itself drew incidents: the idle-alarm guard had 8 against it (4 false alarms); the answer linter had I-232; scrubbers mangled text (I-139, I-194, I-228) | CONFIRMED, loop-distillation §6.3; COUNTED |
| Flaky tests filed four times as new incidents (I-128, I-133, I-135, I-138) before join-on-dedup | CONFIRMED, loop-distillation §6.3 |
| Load from parallel test suites contaminated every A/B of one evening (load 58 on 8 cores) | CONFIRMED, `v1:research/architecture/postmortem-2026-09-30-overload.md` |

### B.2 What worked and must be kept (with v1's enforcer, and the v2 form)

| Keep | Why (v1 evidence) | v1 enforcer | v2 form (INFERRED) |
|---|---|---|---|
| Frozen baseline pinned by hash; tools refuse an unpinned build; results name the snapshot | Pin changed exactly twice, both on purpose | Exit-3 refusal, deny rules, pre-commit, scope guard | Pin the **original mirror** (reference) and each **rewrite release** by hash; every result names both plus its flag set |
| Changes as overlays, one patch per fix | Clean A/B arms | `fix.mjs` | Overlays become **flag arms** in the rewrite. A build ID is the commit plus the flag vector |
| One worktree per agent, one lander, rebase and fast-forward only | 0 merge commits in 2,483 | Git hooks, `reference-transaction`, git-guard | Same |
| One measurement lock; quiet-host admission gate (CPU ticks, load1, memory pressure); a contamination flag on every result | Overload evening: all 9 A/Bs invalid | Lock takes itself; `--no-lock` denied | Same. Lock policy as a pure function (Lean target, §B.5) |
| A/A noise floor; "better" only if ranges are disjoint over ≥3 runs; ±4 ms twin thresholds ("threshold-sensitive") | g0.0l vs g0.0m counted as level, not a win | `ab` verdict rule | Verdict function specified and proved (§B.5) |
| Cards before data: prediction ledger, attribution card (positive and negative ablation plus mechanism check), device class | 13 day-1 lessons; ≥17 flagged prediction misses in 153 rows | Partly mechanical, partly lead discipline | Card schema checked by a tool (v1's own N8 `ticket check` idea) |
| Platform-claim status (OBSERVED, CONFIRMED, REFUTED, UNRESOLVED, WEAKENED); mechanism and attribution kept apart; "WebKit main ≠ iOS 26.6.1" | The `layerPainted` claim (C1) reached the user as fact on two probes | Findings `--claim` field | Same, with a `references/` store indexed by engine and commit (§D) |
| Read source first (WebKit, Chromium, via `gh`), cite path + line + commit | Web search ran out; source answered | Memory note | Same; vendored sparse source snapshots in the repo |
| Incidents deduped by masked first error line; a second reporter joins | Saved double debugging | `incident.mjs` | Same, as a pure dedup function |
| Memory notes: Rule / Why (event and thread) / How / History; per audience | Survived compactions | Convention, plus tools for the rules broken twice | Same; split by role (§B.3) |
| "Every rule has an enforcer or is labelled a convention" | Enforced rules held; prose rules slipped (answer format, fg commands, phone steps, named spawns) | n/a | A rule table with an "Enforced by" column, checked by a test |
| Less-work landing rule: counts plus a short device no-worse check | Gates sized to risk | Memory note | The **default**, with the full protocol only for smoothness claims |
| Pixel tolerance tiers T0/T1/T2, screencast capture, frozen frames, A/A pairs | False "0 %" passes after a scroll (P14) | PR-010 rules | Same for the rewrite's fidelity gate |
| Proposals with live Try-it pages; blind swipe A/B with a catch pair | Look changes are the user's decision; the thumb caught what Chrome missed | `proposal post` refuses an option without Try-it (I-109) | The console's Proposals view (shadcn) |
| One owner per question; named spawns (`<role>-<topic>`) as the address; background waits | Lead answered 13 of 20 messages in threads owned by others before routing | Router, fg-guard | Same |
| Answer format for the user (answer first, ≤18 lines, "What you need to do" last) | Readability complaints stopped | `answer-lint.mjs` | Same |

Sources: `v1:research/loop-distillation/README.md` §3, §6.1, §6.3, §7; `v1:research/architecture/measurement-protocol-v2.md`
§2-§4; `v1:research/architecture/claims-audit.md` §3; `v1:memory/*.md`.

### B.3 Anti-patterns to avoid

1. **One growing rulebook every agent loads.**
   - `CLAUDE.md` went from 1,289 to 9,692 words: ~12-16k tokens re-read per turn.
   - That is ESTIMATED at ~2.1 G tokens, or ~8 % of all cache reads (loop-distillation §6.2).
   - It still contradicts a memory note (`fix.mjs ab` as the standard workflow vs the timing deferral).
   - v1's own fix: a core of about 1,500 words plus per-role notes, and every new rule removes or merges an old one.
2. **Rules added per incident, never removed.** The 40-line lock contract appeared three times. Lock fine print for
   more than ten incidents sat in every agent's context.
3. **Agents writing state the tools already know.**
   - 575 board writes a day; median 9 min lag after a user answer; 7 of 19 over 10 min.
   - Fix: derive the board from events, with one append-only event log and projections. Proposed in v1 as L1-L2 of
     `team-ops-plan.md` §5 and never built.
4. **The lead as router and relay.**
   - 89 of 92 queue moves on 4 Oct.
   - 52 % of output tokens in one 5 h window.
   - 88 of 88 user messages woke the lead before routing.
5. **Too many agents.**
   - 160 agents started in the first 29 h.
   - Throughput was set by the devices, so more agents meant longer queues and more host load.
6. **Measuring on a loaded host and bypassing the lock.** A "niced" test exception with no budget or expiry caused the
   load-58 evening (postmortem root causes 1-2).
7. **Timing-dependent tests on fake real-time.** 47 incidents mention flaky or timing tests. Tests "wait on fake
   real-time phases, timers and polls far more than they compute" (postmortem §3(b), the 2026-10-03 note). Use
   injected clocks instead.
8. **Large modules with side effects at import, duplicated helpers with different meanings** (median vs upper median;
   null-safe vs not). Exit and signal cleanup was spread over five files (`tools-refactor.md` §3).
9. **A refactor plan that never runs.** The plan was written on day 1 and deferred behind in-flight work. The code grew
   about 4x since.
10. **A single probe or one A/A becomes a rule.** Claims C1-C4 (`claims-audit.md` §1.4).
11. **Wrong axis or bundled changes.**
    - Morph frames were binned by `m` instead of by time since start.
    - Blur was scored by rAF gaps.
    - Several fixes were bundled per build.
    - A first-frame gate at n=4 vetoed builds that were better everywhere else (KD L28).
12. **Recurring check prompts answered by the lead's long context** (~200 M tokens over ~490 runs). A script would have
    done it (loop-distillation §6.5).
13. **Side work accepted without its cost stated** (retrospective C8): seven tool features in 2 h, each with a
    toolsmith, a review and a full suite on the shared host.
14. **Hardware faults treated by symptom** instead of root-causing at the source after the first repeat (retrospective
    C3).

### B.4 Agent-team operations: what v1 measured

- **Status.** Agent teams (named teammates) were preferred by the user over the Workflow tool, because the user watches
  and talks to named agents (`v1:memory/agent-teams-not-workflows.md`). The lead's view (loop-distillation §6.4) is
  that fixed gates (pixel gates, cost cards, phone-block readers) would be cheaper and more deterministic as scripts
  than as agents that re-read 15k tokens of rules. INFERRED for v2: use teammates for open diagnosis and scripts for
  fixed pipelines.
- **Team-check role.** A short-lived Sonnet agent reads a friction log every ~6 h. One manual round found 6 issues
  that were not yet incidents (team-ops-plan §4, R1).

### B.5 Where Lean can remove v1's bug classes (INFERRED, ranked by incident evidence)

v1's bug-prone logic is mostly small, pure decision functions tangled with file IO, processes and clocks. Lean 4 fits
the decision functions. The IO shell stays thin (TypeScript or Node), and the two are tied by **differential testing**:
the same inputs go through the Lean executable or spec and through the shipped code. "Make the core provable" means
separating it first, which is also the cure for the coupling in §B.1.

| Pure core | v1 incidents or findings in that area | Properties worth stating |
|---|---|---|
| Measurement lock queue policy (FIFO, short lane, shared lane by weight, quiet gate, starvation cap, re-entry) | ~39 lock/queue/lease incidents, incl. I-005 deadlock, I-011 starvation, I-012 hand-edited state, I-113 lost places | Mutual exclusion of timing holds and every other job; FIFO among normal waiters; no starvation (a grant within the gate cap); a short job never waits behind a queued normal job; re-entry by the same owner only |
| A/B verdict (median, ranges, disjointness, n ≥ 3, twins, contamination) | Two medians disagreeing; the verdict branch had **no test** at n ≥ 3 (`tools-refactor.md` §3) | "better" ⇒ ranges disjoint and n ≥ 3 and not contaminated; a verdict is "threshold-sensitive" iff it flips under ±4 ms; symmetric under swapping arms (sign flips) |
| Frame counting (dt > 34 and > 50, per zone, crossing coordinates) | Duplicate frame summaries in `verify.mjs` and `iphone.mjs`; 60 Hz vs 120 Hz tick confusion (claims-audit P9) | Counts are monotone in the threshold; bins partition frames; zone assignment is total |
| Incident and finding dedup | The same flaky test filed 4 times | The dedup key is idempotent; joining never loses a reporter |
| Thread routing to a listening owner | I-137, I-163 (orphan waits), I-169 (deaf owners) | A message goes to exactly one live owner, else the fallback; never to an ended agent |
| Status board as a projection of events | 8 stale-board incidents; a user decision shown as pending for 16 min (I-145) | A later closing event always overrides an older self-report; the projection is deterministic over the event log |
| Proposal lifecycle (draft → posted → decided → revised, undo) | I-045 (a changed decision notified nobody), I-147 (dropped decision) | Every transition notifies its owner; a decided proposal cannot be landed without Try-it |
| Scrub and redaction rules | I-139, I-191, I-194, I-228, I-269/I-270 follow-ups (release scrub misses) | No secret pattern survives; text outside matches is preserved byte for byte |
| Pixel-tier classifier (T0/T1/T2) | P14 false passes | Blank-strip input can never classify as T0 |
| Engine cost-rule pack (WebKit/Blink rules as data) | 16 rules with file:line (tooling-landscape §5) | Rules versioned by engine build; each rule's statement is a predicate over a style diff, checkable against fixtures |

---

## C. Token and cost data on the v1 agent team

### C.1 Recorded figures

| Figure | Value | Status / source |
|---|---|---|
| Claude Code cost readout, 5 Oct after 4 d 8 h | $8,576 (Opus $8,342, Sonnet $214, Haiku $20) | CONFIRMED article figure, read once |
| Whole project 30 Sep - 9 Oct | ~$13,500, Opus ~97 % | ESTIMATE (readout scaled by token counts) |
| Usage from subagents (5 Oct) | 81 % | CONFIRMED article figure |
| Usage with >150k tokens of context (5 Oct) | 75 % | CONFIRMED article figure |
| Recurring user check prompts | ~200 M tokens over ~490 runs by 5 Oct | CONFIRMED article figure |
| Cache reads as a share of all tokens | 96.3 % | COUNTED from `v1:.git/fastwork-mirror/usage/usage.jsonl` (37 five-hour windows, 1-9 Oct, last record per window) |
| Opus share of weighted units | 97.3 % (Sonnet 2.7 %, Haiku ~0 %) | COUNTED, same file, `byModel` |
| Usage by day (share of weighted units) | 1 Oct 3.5 %, 2 Oct 11.0 %, 3 Oct 14.9 %, **4 Oct 28.6 %**, 5 Oct 16.7 %, 6 Oct 8.5 %, 7 Oct 8.7 %, 8 Oct 6.9 %, 9 Oct 1.2 % | COUNTED, same file (window start dates, UTC) |
| Lead share in one window (4 Oct 07:20-12:20Z) | 52 % of output tokens, 14 % of weighted units, 847 turns; status-board writes ~7 M units a day | CONFIRMED, `team-ops-plan.md` §1.2 |
| Rulebook re-reading | ~2.1 G tokens, ~8 % of cache reads | ESTIMATE, loop-distillation §6.2 |

### C.2 Which roles burned the most

COUNTED from `usage.jsonl`. Method: last record of each 5 h window, `byAgent` summed by name prefix. `byAgent` holds
the top 10 per window, which covers 85 % of all weighted units, so small roles are undercounted. Weighted units =
input + 1.25 × cache writes + 0.1 × cache reads + 5 × output, times a model factor (the `usage.mjs` header).

| Role (name prefix) | Share of all weighted units | Output tokens | Model in v1 |
|---|---|---|---|
| Fix owners (`fix-*`) | 33.2 % | 2.7 M | Opus / high |
| Lead (main session) | 19.7 % | 8.3 M | Opus (session) |
| Management: ops, desk, devices (`mgmt-*`) | 7.5 % | 1.0 M | Opus (ops), Sonnet (devices, later) |
| Toolsmiths (`ts-*`) | 6.7 % | 0.7 M | Opus / high |
| Wave integrators (`int-*`) | 5.3 % | 0.4 M | Opus / high |
| Architecture (`arch-*`) | 4.5 % | 0.4 M | Opus |
| Design engineers / research (`de-*`) | 3.4 % | 0.3 M | Opus or Sonnet |
| iPhone runner | 2.9 % | 0.2 M | Opus |
| Article writers, ops readers, others | ~2 % | small | mixed |
| Reviewers | 0.4 % | 0.1 M | Opus / high |
| Mappers | 0.1 % | ~0 | Sonnet / Haiku |

Top single agents:
- lead 19.7 %;
- mgmt-ops-10 4.7 %;
- fix-hero-exit-threaded 4.6 %;
- int-v8 4.3 %;
- fix-nav-morph 3.5 %;
- arch-compositor-morph 3.4 %;
- iphone-runner 2.9 %.

Reading (INFERRED):
- The cost sits in **long-lived contexts**: the lead, fix owners and ops agents that carry a day of history.
- Reviewers and mappers were cheap even on Opus, because they start fresh and end quickly.
- The per-role model table in `v1:fixes/AGENT_ROLES.md` "Model and effort per task" put almost everything on
  Opus/high. Sonnet was used only for mappers and verifiers, and later the device steward and desk (team-ops-plan R2).

### C.3 Agent-team mechanics that matter for v2's committed config

v1 verified these against the Claude Code docs (v2.1.286, 2026-10-01; `v1:fixes/AGENT_ROLES.md` "How spawning works"),
plus two incidents. Status: CONFIRMED for v1's version. Re-verify against current docs before v2 depends on them.

- `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` was set in the committed `v1:.claude/settings.json` `env`. The same file
  also held `worktree.baseRef: head`, 28 allow, 20 ask and 80 deny rules, and PreToolUse hooks (`git-guard.mjs` 842
  lines, `fg-guard.mjs` 230 lines).
- **Teammates honour** a definition's `tools`, `model` (unless the spawn prompt names one) and its body. They do **not**
  honour `effort` (teammates follow the lead's effort level), `isolation`, `skills`, `permissionMode` or in-process
  `mcpServers`.
  - So per-team effort cannot be set in an agent definition for teammates.
  - Either the lead's `/effort` sets it for all teammates, or the role runs as a **subagent** (which honours `effort`
    and `isolation`).
  - v1 spawned toolsmiths and integrators as worktree subagents for this reason.
- **Teammates cannot spawn teammates.** Their subagents run in the foreground. Subagents can nest 3 levels
  (`CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH`), with at most 20 concurrent.
- **Model resolution order:** per-call `model` → definition `model` → `CLAUDE_CODE_SUBAGENT_MODEL` → the lead's model.
  Haiku supports no effort setting. Opus 5.5 defaults to `medium` effort.
- **Agent types load at session start.** A session started before `.claude/agents/` existed must restart to see them.
  For this reason v1 ran everything as `general-purpose` plus "read the definition first".
- **Names must be unique per session.** A reused name re-resolves to the newest agent. After a context compaction the
  lead stopped passing names (`v1:memory/agent-spawn-names.md`).
- **I-272:** `EnterWorktree` called by a teammate switches the whole session, and earlier worktrees become unwritable.
  Teammates must work by absolute worktree paths that the lead creates.
- **I-274:** idle teammates are not woken by their own background-task notifications.
- **Every permission prompt from a teammate surfaces in the lead's session.**

### C.4 INFERRED cost levers for v2

- Put model and effort on roles that **start fresh and end quickly** (reviewers, verifiers, mappers, schedulers).
  Avoid long-lived Opus contexts. "Fewer agents alive at once, each living as long as its question"
  (loop-distillation §6.6.3).
- Lookups, routing, status, "is the device connected?" and recurring checks go to scripts first, then Haiku or Sonnet.
  Never to the lead's context.
- Keep the always-loaded rulebook at ~1,500 words. Put role notes in agent bodies.
- Every agent role carries a usage budget, and the usage meter attributes by role from day 1 (v1's `usage.mjs` method).

---

## D. Reusable ideas, not code

| v1 idea | Where it is described | How v2 can reuse it (INFERRED) |
|---|---|---|
| Staged recipe (day 0: freeze, overlays, worktrees, one lock, short rulebook, two guards, shared boards, device + human queue; week 1 add-on signals) | `v1:research/loop-distillation/README.md` §7 | Use it as the v2 bootstrap checklist |
| Two-speed loop: deterministic counts inside, device outside | `lead-retrospective-24h.md` §5.1 | The engine-math model plus Chrome/WebKit counts are the inner loop; the device is outside |
| Cost card (layouts, paints, layers, rAF per 6 s rest window, per event) | `v1:memory/less-work-landing-rule.md`; `tools/costcard.mjs` (idea only) | A CI budget per flag arm |
| Rest-and-flip probe (animations and rAF at rest, two writers per property, presence flips, several state changes per scroll bucket) | `tooling-landscape` §6 Build 1 | A dev-mode React probe, runnable in Safari and the Simulator |
| WebKit rule pack (16 rules, version-tagged) | `tooling-landscape` §5-6 | Seed for the stylelint/ESLint pack and for Lean-encoded rule data |
| Element ablation with a fairness check | `v1:research/element-ablation/README.md` | Flag arms of the `off(ablation)` kind |
| Crossing coordinates (place frames by the nearest code threshold, not raw y) | `measurement-protocol-v2.md` §3.4 | Every flagged element declares its thresholds; the probe logs crossings |
| Attribution card: positive and negative ablation, mechanism check, axis decoupling run, device class | `measurement-protocol-v2.md` §2.3 | Card schema in the console backend, validated by code |
| Phone-block protocol (C V V C, warm-up, sentinel, kit hashed, predictions frozen) | `measurement-protocol-v2.md` §5 | Keep for the small device budget |
| Safari probing over the WebKit inspector protocol (`Page.enable` before `Timeline.start`; `LayerTree.layersForNode` gives `paintCount` and `memory`; Instruments for render-server time) | `v1:research/architecture/safari-inspector-probing.md` §0 | Foundation of v2's WebKit stats collector |
| Validated perception metric: frames >50 ms per 100 moving frames in the finger's zone (7/7) | `stats-vs-finger.md` | Primary device metric; a validity table for every proxy |
| Host-quiet gate on CPU ticks, memory pressure and load1, with a per-run contamination flag | `postmortem-2026-09-30-overload.md` §3 | Same, in the measurement lock |
| One event log with projections; one inbox wait per agent | `team-ops-plan.md` §5 L1-L2 | The console backend's core design, a natural Lean target |
| Read-cost metric for tools (tokens to answer 12 standard questions; contract headers; a tools map with a test) | `tools-refactor.md` §2, §5 | A day-1 rule for v2 code: a contract header per module, a map file checked by a test |
| Claims audit with WEAKENED and engine-build applicability | `claims-audit.md` §2-§3 | A `references/` store keyed by engine and commit |
| Memory note format and audiences | `v1:memory/README.md` | Same |
| Proposal with Try-it and user decision as spec | `v1:memory/proposal-*.md` | The console Proposals view |

---

## E. Open questions for the user

1. **The fidelity target for the rewrite.** Must the React rewrite reproduce the original's **costs** (so v1's
   experiments can be re-run as flag arms), or only its **look**? The answer decides whether every element needs an
   `original` mechanism arm (§A.5).
2. **The device budget.** Is a small, scheduled real-device budget acceptable as the outer loop, for example one phone
   block per candidate stack, with the engine-math model screening everything else? Or must v2 run with no device at
   all?
3. **The scope of Lean.** Should proofs cover the console backend's pure core (lock, verdict, routing, projections),
   or the engine cost model as well? The second needs engine rules encoded as versioned data.
4. **Per-team effort.** Agent-team teammates follow the lead's effort level. Is it acceptable to run cost-sensitive
   roles as subagents, which honour `effort`? Or should the lead's `/effort` be set per phase?
5. **Is v1's best build the "target look"?** Its end of page and People reveal differ from the original in two places
   the user chose (finger-following menu, instant card after a flick).

---

## Sources

All in the v1 repo `../fastwork-com-web-optimize` (read-only), read 2026-10-17:

- `research/loop-distillation/README.md` (§1-§8)
- `research/knowledge-distillation/README.md` (lessons 1-30, platform facts table §6)
- `research/tooling-landscape/README.md` (§3 coverage map, §5 WebKit rules with file:line, §6 recommendation)
- `research/architecture/README.md` (2026-10-01 review, moves 0-7)
- `research/architecture/postmortem-2026-09-30-overload.md`
- `research/architecture/tools-refactor.md` (Appendix A baseline)
- `research/architecture/team-ops-plan.md` (§1 slips, §1.2 tokens, §5 plan)
- `research/architecture/measurement-protocol-v2.md` (§1-§4)
- `research/architecture/claims-audit.md` (§1.4, §2.5, §3)
- `research/architecture/gpu-compositor-playbook.md` (§3, §7)
- `research/architecture/safari-inspector-probing.md` (§0)
- `research/architecture/stats-vs-finger.md`
- `research/management/lead-retrospective-24h.md` (C1-C8, §4-§5)
- `research/cpu-throttle-calibration/README.md`; `research/simulator/README.md`; `research/element-ablation/README.md`
- `research/team-article/artifacts/building-an-ai-loop-from-scratch.html` ("What it cost")
- `fixes/AGENT_ROLES.md` (roster, "How spawning works", "Model and effort per task"); `fixes/BEST_BUILDS.md`
- `CLAUDE.md` (section list, "Tooling is guarded by tests"); `memory/README.md` and the notes named above
- `.claude/settings.json`; `.claude/agents/{bundle-mapper,fix-owner,fix-reviewer,toolsmith,wave-integrator}.md`
- `package.json` (test scripts); `tools/scope.mjs` header; `tools/lib/` listing
- `console/incidents.json` (276 records; classification script in this session's scratchpad, regex over titles)
- `.git/fastwork-mirror/usage/usage.jsonl` (435 records, 1-9 Oct; counts only, no transcript text)
