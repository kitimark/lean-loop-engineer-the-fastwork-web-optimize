import Fw.Parts.EngineScroll
import Fw.Parts.FootprintData
import Fw.Parts.FootprintRows

/-! Part contract table: one `PartSpec` row per part id under `apps/site/src/parts`, the independence premises I1-I4
(plan section B; I5 recorded, not proved), the groups, and the measurement profiles each part runs under.
`lean/scripts/ContractsGolden.lean` renders it to `packages/contracts/golden/parts/contracts.gen.json` and
`packages/measure-chromium/scenarios.gen.json`. Row cites are paths under `apps/site/src/parts/`. -/

namespace Fw.Parts.Contract

open Fw.Parts.EngineScroll (Access forced styleRole layoutRole)

/-- A value a part reads or writes at frame time. `cssVar n` is a custom or inline style property, `className n` a class
or attribute token; both names carry `/owner`, the part id that renders the element they sit on. `rect n` is a box
read of part `n`'s element.

$$\sigma \in \{\mathrm{scrollY}, \mathrm{vw}, \mathrm{vh}, \mathrm{clock}, \mathrm{pointer}, \mathrm{morphPhase},
\mathrm{cssVar}(n), \mathrm{className}(n), \mathrm{rect}(n), \mathrm{scenePaused}\}$$

`pointer` covers pointer, wheel and touch input; `scenePaused` is engine.scene's `data-fw-hidden` on the platform. -/
inductive Signal
  | scrollY | vw | vh | clock | pointer | morphPhase
  | cssVar (name : String) | className (name : String) | rect (name : String) | scenePaused
deriving Repr, DecidableEq

/-- Coupled groups G1-G5 of plan section B, plus `solo` for a part that forms its own group.

$$g \in \{G_1, G_2, G_3, G_4, G_5, \mathrm{solo}\}$$

G1 hero/threshold, G2 morph, G3 page-offset chain, G4 page-level scheduling, G5 commission/resize. -/
inductive Group | g1 | g2 | g3 | g4 | g5 | solo
deriving Repr, DecidableEq

/-- Short name of a group. $$\operatorname{name}(G_i) = \texttt{g}i,\ \operatorname{name}(\mathrm{solo}) = \texttt{solo}$$
The string used in the goldens and as a group key. -/
def Group.name : Group → String
  | .g1 => "g1" | .g2 => "g2" | .g3 => "g3" | .g4 => "g4" | .g5 => "g5" | .solo => "solo"

/-- One part's contract. `targets`: part ids owning the elements it writes at frame time (mount, resize and click/key
writes excluded). `moves`: part ids whose boxes its frame writes move under a fixed viewport. `listAccess`: the
accesses its scroll-list callback performs inline under the faithful engine variant, in order (`[]` when it only
requests its own frame). `onEvent`: outputs written only by click/key handlers. `plan`: the plan's group for the part.
`schedules`: its variant changes the scroll-list schedule of every registered part.

$$P = (\mathrm{id}, g, g_{\mathrm{plan}}, o, \mathrm{in}, \mathrm{out}, \mathrm{ev}, T, M, A, \ell, s),\quad
o \in \mathbb{N} \cup \{\bot\}$$

The declared inputs, outputs and write footprint the independence premises are decided on. Accepted limits (judge
against these, do not reopen them): `outputs` list only signals another part can read (own-element aria, viewBox and
tabIndex writes are excluded); I4 is pairwise with no clock-subscriber order; event-only writes are excluded
(overlays' body overflow); a box move is hand-listed in `moves` (gate PL1 witnesses it; part-io-lint checks code
against declared writes, not which boxes a write moves); `vw` and `vh` have no writer; I5 layerization is a recorded
premise; dead selectors under hashed CSS-module names are recorded in the row docstrings. Certified relative to the
declared rows; row completeness is an unverified premise (contract-rows-from-code / part-io-lint). -/
structure PartSpec where
  id : String
  group : Group
  plan : Group
  order : Option Nat := none
  inputs : List Signal := []
  outputs : List Signal := []
  onEvent : List Signal := []
  targets : List String := []
  moves : List String := []
  listAccess : List Access := []
  layoutLocal : Bool := true
  schedules : Bool := false
deriving Repr

open Signal Fw.Parts.EngineScroll.Access

/-- Contract row of `commission`.

$$g = G_2,\ g_{\mathrm{plan}} = G_5,\ o = 50,\ \ell = \top,\ s = \bot,
\mathrm{in} = [\texttt{rect:commission}, \texttt{vh}, \texttt{vw}, \texttt{clock}],\ \mathrm{out} = [\texttt{cssVar:--commission-enter-shrink/commission}, \texttt{cssVar:--commission-shrink/commission}, \texttt{className:entering/commission}, \texttt{className:shrinking/commission}, \texttt{cssVar:height/commission}, \texttt{className:titleWrapped/commission}, \texttt{className:enter/commission}, \texttt{className:idle/commission}, \texttt{className:data-scene/commission}, \texttt{className:data-render/commission}, \texttt{cssVar:--start-selling-intrinsic-block-size/commission}],\ \mathrm{ev} = [\,],
T = [\texttt{commission}],\ M = [\,],\ A = [\texttt{RL}, \texttt{RL}, \texttt{WS}, \texttt{WS}, \texttt{WS}, \texttt{WS}, \texttt{WL}, \texttt{RL}, \texttt{WS}]$$

commission/driver.ts:4,199-206 order 50, inline body 123-138 (rect reads 127-128, shrink vars and the entering and
shrinking classes 131-134, runway height 135, line-box read and title class 118-121); underline classes 171-172 on the
clock interval, own frame 110; data-scene 161,196, intrinsic size 155; vw is the `mq.c1000` match (index.tsx:44,53). The
runway is `RUNWAY * vh` (logic.ts:71), fixed for a fixed viewport, so `moves` is empty. Joins G2 by I4: its callback
ends with a style write and platform (95) starts with a rect read. -/
def commission : PartSpec :=
  { id := "commission", group := .g2, plan := .g5, order := some 50,
    inputs := [rect "commission", vh, vw, clock],
    outputs := [cssVar "--commission-enter-shrink/commission", cssVar "--commission-shrink/commission",
      className "entering/commission", className "shrinking/commission", cssVar "height/commission",
      className "titleWrapped/commission", className "enter/commission", className "idle/commission",
      className "data-scene/commission", className "data-render/commission",
      cssVar "--start-selling-intrinsic-block-size/commission"],
    targets := ["commission"],
    listAccess := [readLayout, readLayout, writeStyle, writeStyle, writeStyle, writeStyle, writeLayout, readLayout,
      writeStyle] }

/-- Contract row of `commission.typing`.

$$g = G_2,\ g_{\mathrm{plan}} = \mathrm{solo},\ o = \bot,\ \ell = \top,\ s = \bot,
\mathrm{in} = [\texttt{clock}, \texttt{rect:commission.typing}, \texttt{className:data-scene/commission}],\ \mathrm{out} = [\texttt{cssVar:--visual-scale/commission.typing}],\ \mathrm{ev} = [\,],
T = [\texttt{commission.typing}],\ M = [\,],\ A = [\,]$$

commission.typing/driver.ts:99 clock, index.tsx:54-62 observers, driver.ts:63-80,104 own classes, fill width and
`--visual-scale`; paused by commission's `data-scene` (commission/commission.module.css:19-20). -/
def commissionTyping : PartSpec :=
  { id := "commission.typing", group := .g2, plan := .solo,
    inputs := [clock, rect "commission.typing", className "data-scene/commission"],
    outputs := [cssVar "--visual-scale/commission.typing"], targets := ["commission.typing"] }

/-- Contract row of `engine.scene`.

$$g = G_2,\ g_{\mathrm{plan}} = G_4,\ o = \bot,\ \ell = \top,\ s = \bot,
\mathrm{in} = [\texttt{rect:platform}],\ \mathrm{out} = [\texttt{scenePaused}],\ \mathrm{ev} = [\,],
T = [\texttt{platform}],\ M = [\,],\ A = [\,]$$

engine.scene/index.tsx:25-35 hidden-pause writes `data-fw-hidden` on the section App passes
(App.tsx:41, the platform); the rule is engine.scene/scene.module.css:4-6. -/
def engineScene : PartSpec :=
  { id := "engine.scene", group := .g2, plan := .g4,
    inputs := [rect "platform"], outputs := [scenePaused], targets := ["platform"] }

/-- Contract row of `engine.scroll`.

$$g = G_4,\ g_{\mathrm{plan}} = G_4,\ o = \bot,\ \ell = \top,\ s = \top,
\mathrm{in} = [\texttt{scrollY}, \texttt{vw}, \texttt{vh}, \texttt{clock}],\ \mathrm{out} = [\,],\ \mathrm{ev} = [\,],
T = [\,],\ M = [\,],\ A = [\,]$$

engine.scroll/index.tsx:12 sets the scroll engine variant (engine/scroll.ts), which hero.exit/driver.ts:67,71 and
every registered callback run under; the `data-fw` write (index.tsx:17-20) is mount-time. -/
def engineScroll : PartSpec :=
  { id := "engine.scroll", group := .g4, plan := .g4, inputs := [scrollY, vw, vh, clock], schedules := true }

/-- Contract row of `hero`.

$$g = G_1,\ g_{\mathrm{plan}} = G_1,\ o = \bot,\ \ell = \top,\ s = \bot,
\mathrm{in} = [\texttt{cssVar:--exit-opacity/hero.exit}, \texttt{className:data-splash/hero.exit}],\ \mathrm{out} = [\,],\ \mathrm{ev} = [\,],
T = [\,],\ M = [\,],\ A = [\,]$$

hero/hero.module.css:19-21,197,199 read `--exit-opacity` (and `--exit-scatter`, derived from it) set by hero.exit;
31,34 read `data-splash` on hero.exit's stage. -/
def hero : PartSpec :=
  { id := "hero", group := .g1, plan := .g1,
    inputs := [cssVar "--exit-opacity/hero.exit", className "data-splash/hero.exit"] }

/-- Contract row of `hero.accent`.

$$g = G_1,\ g_{\mathrm{plan}} = \mathrm{solo},\ o = \bot,\ \ell = \bot,\ s = \bot,
\mathrm{in} = [\texttt{clock}, \texttt{rect:hero.accent}],\ \mathrm{out} = [\texttt{cssVar:width/hero.accent}],\ \mathrm{ev} = [\,],
T = [\texttt{hero.accent}],\ M = [\texttt{hero}],\ A = [\,]$$

hero.accent/index.tsx:35-50 per-frame em and frame width writes on the clock, 54 stand-in path, 59-60 observer;
the width change moves the sibling words of hero's h1 (hero/index.tsx:55). -/
def heroAccent : PartSpec :=
  { id := "hero.accent", group := .g1, plan := .solo,
    inputs := [clock, rect "hero.accent"], outputs := [cssVar "width/hero.accent"],
    targets := ["hero.accent"], moves := ["hero"], layoutLocal := false }

/-- Contract row of `hero.countdown`.

$$g = \mathrm{solo},\ g_{\mathrm{plan}} = \mathrm{solo},\ o = \bot,\ \ell = \top,\ s = \bot,
\mathrm{in} = [\texttt{clock}, \texttt{vw}],\ \mathrm{out} = [\texttt{cssVar:--cell/hero.countdown}],\ \mathrm{ev} = [\,],
T = [\texttt{hero.countdown}],\ M = [\,],\ A = [\,]$$

hero.countdown/index.tsx:63 `Date.now`, 89-97 ResizeObserver, 93 `--cell`, 105 clock; driver.ts:64,67 transforms,
all inside its own anchor. -/
def heroCountdown : PartSpec :=
  { id := "hero.countdown", group := .solo, plan := .solo,
    inputs := [clock, vw], outputs := [cssVar "--cell/hero.countdown"], targets := ["hero.countdown"] }

/-- Contract row of `hero.cue`.

$$g = G_1,\ g_{\mathrm{plan}} = \mathrm{solo},\ o = \bot,\ \ell = \top,\ s = \bot,
\mathrm{in} = [\texttt{cssVar:--exit-opacity/hero.exit}, \texttt{className:data-splash/hero.exit}],\ \mathrm{out} = [\,],\ \mathrm{ev} = [\texttt{scrollY}],
T = [\,],\ M = [\,],\ A = [\,]$$

hero.cue/cue.module.css:8-11,79,87-88 read `--exit-opacity`/`--exit-scatter`, 23,85 read `data-splash`; the click
`scrollTo` (index.tsx:9-10) is event-only. -/
def heroCue : PartSpec :=
  { id := "hero.cue", group := .g1, plan := .solo,
    inputs := [cssVar "--exit-opacity/hero.exit", className "data-splash/hero.exit"], onEvent := [scrollY] }

/-- Contract row of `hero.deck`.

$$g = G_1,\ g_{\mathrm{plan}} = \mathrm{solo},\ o = \bot,\ \ell = \top,\ s = \bot,
\mathrm{in} = [\texttt{cssVar:--exit-opacity/hero.exit}, \texttt{className:data-splash/hero.exit}],\ \mathrm{out} = [\,],\ \mathrm{ev} = [\,],
T = [\,],\ M = [\,],\ A = [\,]$$

hero.deck/index.tsx renders hero.orbit's HeroCard, whose hero.orbit/card.module.css:20,29-30 read `--exit-scatter`
and `data-splash`. -/
def heroDeck : PartSpec :=
  { id := "hero.deck", group := .g1, plan := .solo,
    inputs := [cssVar "--exit-opacity/hero.exit", className "data-splash/hero.exit"] }

/-- Contract row of `hero.exit`.

$$g = G_1,\ g_{\mathrm{plan}} = G_1,\ o = 10,\ \ell = \top,\ s = \bot,
\mathrm{in} = [\texttt{rect:hero.exit}, \texttt{vh}, \texttt{clock}],\ \mathrm{out} = [\texttt{cssVar:--exit-opacity/hero.exit}, \texttt{cssVar:pointer-events/hero.exit}],\ \mathrm{ev} = [\,],
T = [\texttt{hero.exit}],\ M = [\,],\ A = [\,]$$

hero.exit/driver.ts:41,66-68 order 10, faithful callback only requests its own frame; body 21-25 reads the track
rect and writes `--exit-opacity` and pointer-events on the stage (index.tsx:34-35); vh index.tsx:30. -/
def heroExit : PartSpec :=
  { id := "hero.exit", group := .g1, plan := .g1, order := some 10,
    inputs := [rect "hero.exit", vh, clock],
    outputs := [cssVar "--exit-opacity/hero.exit", cssVar "pointer-events/hero.exit"], targets := ["hero.exit"] }

/-- Contract row of `hero.orbit`.

$$g = G_1,\ g_{\mathrm{plan}} = \mathrm{solo},\ o = \bot,\ \ell = \top,\ s = \bot,
\mathrm{in} = [\texttt{clock}, \texttt{vw}, \texttt{pointer}, \texttt{cssVar:--exit-opacity/hero.exit}, \texttt{className:data-splash/hero.exit}],\ \mathrm{out} = [\texttt{className:data-splash/hero.exit}, \texttt{cssVar:--orbit-enter-x/hero.orbit}, \texttt{cssVar:--orbit-enter-y/hero.orbit}, \texttt{cssVar:--orbit-start-rot/hero.orbit}, \texttt{cssVar:--ring-motion-blur/hero.orbit}],\ \mathrm{ev} = [\,],
T = [\texttt{hero.exit}, \texttt{hero.orbit}],\ M = [\,],\ A = [\,]$$

hero.orbit/driver.ts:70,90,93 write `data-splash` on hero.exit's stage, 51-53,75 own orbit vars, 99 clock;
index.tsx:50 pointer, 75 innerWidth; card.module.css:20,29-30 read `--exit-scatter`. -/
def heroOrbit : PartSpec :=
  { id := "hero.orbit", group := .g1, plan := .solo,
    inputs := [clock, vw, pointer, cssVar "--exit-opacity/hero.exit", className "data-splash/hero.exit"],
    outputs := [className "data-splash/hero.exit", cssVar "--orbit-enter-x/hero.orbit",
      cssVar "--orbit-enter-y/hero.orbit", cssVar "--orbit-start-rot/hero.orbit", cssVar "--ring-motion-blur/hero.orbit"],
    targets := ["hero.exit", "hero.orbit"] }

/-- Contract row of `morph.columns`.

$$g = \mathrm{solo},\ g_{\mathrm{plan}} = G_2,\ o = \bot,\ \ell = \top,\ s = \bot,
\mathrm{in} = [\texttt{rect:morph.columns}, \texttt{className:data-fw-hidden/morph.columns}],\ \mathrm{out} = [\texttt{className:data-fw-hidden/morph.columns}],\ \mathrm{ev} = [\,],
T = [\texttt{morph.columns}],\ M = [\,],\ A = [\,]$$

morph.columns/index.tsx:5 imports engine.scene's global rule itself, 38-52 writes `data-fw-hidden` on its own stage
from its own observer; morph.module.css:18 names `--morph` only in a comment, 24 own `data-scene`. -/
def morphColumns : PartSpec :=
  { id := "morph.columns", group := .solo, plan := .g2,
    inputs := [rect "morph.columns", className "data-fw-hidden/morph.columns"],
    outputs := [className "data-fw-hidden/morph.columns"], targets := ["morph.columns"] }

/-- Contract row of `morph.countdown`.

$$g = \mathrm{solo},\ g_{\mathrm{plan}} = G_2,\ o = \bot,\ \ell = \top,\ s = \bot,
\mathrm{in} = [\texttt{clock}, \texttt{rect:morph.countdown}, \texttt{className:data-start-selling-scene/morph.panel}],\ \mathrm{out} = [\texttt{cssVar:transform/morph.countdown}],\ \mathrm{ev} = [\,],
T = [\texttt{morph.countdown}],\ M = [\,],\ A = [\,]$$

morph.countdown/index.tsx:23-34 write gate on its own HeroCountdown transforms, 38 own observer; rendered inside
morph.panel (App.tsx:56-60); morph.module.css:14-15 pauses on the panel's `data-start-selling-scene`. -/
def morphCountdown : PartSpec :=
  { id := "morph.countdown", group := .solo, plan := .g2,
    inputs := [clock, rect "morph.countdown", className "data-start-selling-scene/morph.panel"],
    outputs := [cssVar "transform/morph.countdown"],
    targets := ["morph.countdown"] }

/-- Contract row of `morph.mount`.

$$g = G_2,\ g_{\mathrm{plan}} = \mathrm{solo},\ o = 101,\ \ell = \top,\ s = \bot,
\mathrm{in} = [\texttt{scrollY}, \texttt{vh}, \texttt{pointer}, \texttt{rect:morph.mount}],\ \mathrm{out} = [\,],\ \mathrm{ev} = [\,],
T = [\texttt{morph.mount}],\ M = [\,],\ A = [\texttt{RL}]$$

morph.mount/index.tsx:103-106 order 101 (logic.ts:72) reads `window.scrollY` on every call, which updates style
and layout (chromium third_party/blink/renderer/core/frame/local_dom_window.cc:1877@f842f52); the repin writer needs
`isActive`, false by default (index.tsx:34, App.tsx:37); 55-56 visual viewport height, 81-83 wheel/touch, 93 observer
on its own div (139). -/
def morphMount : PartSpec :=
  { id := "morph.mount", group := .g2, plan := .solo, order := some 101,
    inputs := [scrollY, vh, pointer, rect "morph.mount"], targets := ["morph.mount"], listAccess := [readLayout] }

/-- Contract row of `morph.panel`.

$$g = \mathrm{solo},\ g_{\mathrm{plan}} = G_2,\ o = \bot,\ \ell = \top,\ s = \bot,
\mathrm{in} = [\texttt{cssVar:--morph/morph.panel}],\ \mathrm{out} = [\,],\ \mathrm{ev} = [\,],
T = [\texttt{morph.panel}],\ M = [\,],\ A = [\,]$$

morph.panel/index.tsx:33-44 own writer, App.tsx:56-60 passes no `writerRef`; its host sets `--morph: 0` itself
(morph.module.css:8-9) and sits outside the nav, so nav's `--morph` does not reach it. Its `data-start-selling-scene`
(driver.ts:24, index.tsx:37,54) is mount-only today; once a `writerRef` drives it per frame (morph-group-integrate)
the attribute becomes an output that morph.countdown reads. -/
def morphPanel : PartSpec :=
  { id := "morph.panel", group := .solo, plan := .g2,
    inputs := [cssVar "--morph/morph.panel"], targets := ["morph.panel"] }

/-- Contract row of `morph.tween`.

$$g = G_2,\ g_{\mathrm{plan}} = G_2,\ o = 110,\ \ell = \top,\ s = \bot,
\mathrm{in} = [\texttt{scrollY}, \texttt{vh}, \texttt{clock}, \texttt{pointer}, \texttt{rect:platform}],\ \mathrm{out} = [\texttt{cssVar:--morph/nav}, \texttt{morphPhase}, \texttt{cssVar:--morph-fade/platform}, \texttt{cssVar:pointer-events/platform}, \texttt{scrollY}],\ \mathrm{ev} = [\,],
T = [\texttt{nav}, \texttt{platform}],\ M = [\,],\ A = [\texttt{RL}]$$

morph.tween/index.tsx:55 order 110, `pin` (driver.ts:141-142) reads `scrollY` and `scrollTo`s while active;
index.tsx:44-49 `--morph` and `data-fw-morph` on the nav; driver.ts:56-57,62 `--morph-fade`, pointer-events and the
platform rect; 89-91 wheel/touch, 130 clock. Its `scrollY` output makes it page-level (`pageLevel`): the pin moves
every rect, so it couples to every rect reader (`scroll_writer_couples`) and its own variants are measured only on
whole-page runs. -/
def morphTween : PartSpec :=
  { id := "morph.tween", group := .g2, plan := .g2, order := some 110,
    inputs := [scrollY, vh, clock, pointer, rect "platform"],
    outputs := [cssVar "--morph/nav", morphPhase, cssVar "--morph-fade/platform", cssVar "pointer-events/platform",
      scrollY],
    targets := ["nav", "platform"], listAccess := [readLayout] }

/-- Contract row of `nav`.

$$g = G_2,\ g_{\mathrm{plan}} = G_1,\ o = 99,\ \ell = \top,\ s = \bot,
\mathrm{in} = [\texttt{rect:hero.exit}, \texttt{rect:people.deck}, \texttt{vh}, \texttt{morphPhase}, \texttt{cssVar:--morph/nav}, \texttt{className:is-on-dark/nav}],\ \mathrm{out} = [\texttt{className:is-hero-pill/nav}, \texttt{className:is-hero-chrome-ready/nav}, \texttt{className:is-morphing/nav}, \texttt{className:is-scroll-hidden/nav}],\ \mathrm{ev} = [\texttt{className:is-locale-open/nav}, \texttt{className:is-expanded/nav}],
T = [\texttt{nav}],\ M = [\,],\ A = [\texttt{RL}, \texttt{WS}]$$

nav/index.tsx:11,106 order 99, `measure` reads first and returns a writer (driver.ts:27,76-79); hero-exit rect
index.tsx:55,75-77, morph phase 84, classes 88 (logic.ts:88-95); nav.module.css reads `--morph`, `is-on-dark`
(56,59); locale and expand classes are click-driven (driver.ts:94-95). `measureSticky` (index.tsx:28-39) reads the
rect of `#profile-showcase`, people.deck's section (people.deck/index.tsx:108), listed as a may-read. Dead selectors:
`.start-selling-profile-sticky` and `.hero.is-ring-splash-done` (index.tsx:56-57) match no element in apps/site,
whose CSS-module names are hashed (apps/site/scripts/build.mjs:41); a content lane that restores a global class name
adds the matching `className`/`rect` inputs. -/
def nav : PartSpec :=
  { id := "nav", group := .g2, plan := .g1, order := some 99,
    inputs := [rect "hero.exit", rect "people.deck", vh, morphPhase, cssVar "--morph/nav", className "is-on-dark/nav"],
    outputs := [className "is-hero-pill/nav", className "is-hero-chrome-ready/nav", className "is-morphing/nav",
      className "is-scroll-hidden/nav"],
    onEvent := [className "is-locale-open/nav", className "is-expanded/nav"],
    targets := ["nav"], listAccess := [readLayout, writeStyle] }

/-- Contract row of `nav.hitTest`.

$$g = G_2,\ g_{\mathrm{plan}} = \mathrm{solo},\ o = 100,\ \ell = \top,\ s = \bot,
\mathrm{in} = [\texttt{morphPhase}, \texttt{vh}, \texttt{rect:nav}, \texttt{rect:hero.exit}],\ \mathrm{out} = [\texttt{className:is-on-dark/nav}, \texttt{cssVar:pointer-events/nav}],\ \mathrm{ev} = [\,],
T = [\texttt{nav}],\ M = [\,],\ A = [\texttt{RL}, \texttt{WS}, \texttt{RL}, \texttt{WS}, \texttt{RL}, \texttt{WS}]$$

nav.hitTest/index.tsx:36 order 100 (logic.ts:94), 15 morph phase, 42-45 `is-on-dark` writer; faithful probe
probe.ts:60-66 (rect read, pointer-events write, elementFromPoint, restore) and hero rect 84-87. Dead selectors:
the `closest` selectors (logic.ts:19-21: commission card, future card, hero, pain, platform, `.commission.shrinking`)
and `.start-selling-profile-sticky` (probe.ts:47) match no element in apps/site, whose CSS-module names are hashed
(apps/site/scripts/build.mjs:41); a content lane that restores a global class name adds the `className`/`rect` inputs
for hero, people.card, pain, commission and platform. -/
def navHitTest : PartSpec :=
  { id := "nav.hitTest", group := .g2, plan := .solo, order := some 100,
    inputs := [morphPhase, vh, rect "nav", rect "hero.exit"],
    outputs := [className "is-on-dark/nav", cssVar "pointer-events/nav"], targets := ["nav"],
    listAccess := [readLayout, writeStyle, readLayout, writeStyle, readLayout, writeStyle] }

/-- Contract row of `nav.langMenu`.

$$g = G_2,\ g_{\mathrm{plan}} = \mathrm{solo},\ o = \bot,\ \ell = \top,\ s = \bot,
\mathrm{in} = [\texttt{clock}, \texttt{pointer}, \texttt{className:is-on-dark/nav}],\ \mathrm{out} = [\,],\ \mathrm{ev} = [\texttt{className:is-locale-open/nav}],
T = [\texttt{nav.langMenu}],\ M = [\,],\ A = [\,]$$

nav.langMenu/lang.module.css:36 reads the nav's `is-on-dark` (written by nav.hitTest); index.tsx:40 clock,
65-66 mouse/key; `onOpenChange` (nav/index.tsx:123,135) is event-only. -/
def navLangMenu : PartSpec :=
  { id := "nav.langMenu", group := .g2, plan := .solo,
    inputs := [clock, pointer, className "is-on-dark/nav"], onEvent := [className "is-locale-open/nav"],
    targets := ["nav.langMenu"] }

/-- Contract row of `overlays.drawer`.

$$g = \mathrm{solo},\ g_{\mathrm{plan}} = \mathrm{solo},\ o = \bot,\ \ell = \top,\ s = \bot,
\mathrm{in} = [\texttt{pointer}, \texttt{clock}],\ \mathrm{out} = [\,],\ \mathrm{ev} = [\texttt{cssVar:overflow/body}],
T = [\,],\ M = [\,],\ A = [\,]$$

overlays.drawer/index.tsx:54,66 clock while open, 77-80 body overflow on open/close. -/
def overlaysDrawer : PartSpec :=
  { id := "overlays.drawer", group := .solo, plan := .solo,
    inputs := [pointer, clock], onEvent := [cssVar "overflow/body"] }

/-- Contract row of `overlays.signup`.

$$g = \mathrm{solo},\ g_{\mathrm{plan}} = \mathrm{solo},\ o = \bot,\ \ell = \top,\ s = \bot,
\mathrm{in} = [\texttt{pointer}],\ \mathrm{out} = [\,],\ \mathrm{ev} = [\texttt{cssVar:overflow/body}, \texttt{cssVar:--dialog-dir-x/overlays.signup}, \texttt{cssVar:--dialog-dir-y/overlays.signup}],
T = [\,],\ M = [\,],\ A = [\,]$$

overlays.signup/index.tsx:51-52 dialog direction vars and 63-66 body overflow, both on open. -/
def overlaysSignup : PartSpec :=
  { id := "overlays.signup", group := .solo, plan := .solo,
    inputs := [pointer],
    onEvent := [cssVar "overflow/body", cssVar "--dialog-dir-x/overlays.signup", cssVar "--dialog-dir-y/overlays.signup"] }

/-- Contract row of `pain`.

$$g = G_1,\ g_{\mathrm{plan}} = G_1,\ o = \bot,\ \ell = \top,\ s = \bot,
\mathrm{in} = [\texttt{className:is-pain-dark/pain}, \texttt{className:data-scene/pain}],\ \mathrm{out} = [\,],\ \mathrm{ev} = [\,],
T = [\,],\ M = [\,],\ A = [\,]$$

pain/index.tsx:19 the section; pain.module.css:96-99 reads `is-pain-dark`, pain.notes/notes.module.css:6-13 its
`data-scene`/`data-render`. -/
def pain : PartSpec :=
  { id := "pain", group := .g1, plan := .g1,
    inputs := [className "is-pain-dark/pain", className "data-scene/pain"] }

/-- Contract row of `pain.notes`.

$$g = G_1,\ g_{\mathrm{plan}} = \mathrm{solo},\ o = 120,\ \ell = \top,\ s = \bot,
\mathrm{in} = [\texttt{pointer}, \texttt{clock}, \texttt{vh}, \texttt{rect:pain.notes}, \texttt{rect:pain}],\ \mathrm{out} = [\texttt{cssVar:--start-selling-intrinsic-block-size/pain}, \texttt{className:data-scene/pain}, \texttt{className:data-render/pain}],\ \mathrm{ev} = [\,],
T = [\texttt{pain}, \texttt{pain.notes}],\ M = [\,],\ A = [\,]$$

pain.notes/index.tsx:16,136 order 120, callback runs `onScroll` (driver.ts:156-161) whose only read is the
commission card top (index.tsx:72,81), absent in apps/site; writes on the pain section index.tsx:71,108 and
scene.ts:49,61; note positions 92-94; pointer 131-135, clock 57, rects 75,79-80,102. -/
def painNotes : PartSpec :=
  { id := "pain.notes", group := .g1, plan := .solo, order := some 120,
    inputs := [pointer, clock, vh, rect "pain.notes", rect "pain"],
    outputs := [cssVar "--start-selling-intrinsic-block-size/pain", className "data-scene/pain",
      className "data-render/pain"],
    targets := ["pain", "pain.notes"] }

/-- Contract row of `people`.

$$g = \mathrm{solo},\ g_{\mathrm{plan}} = \mathrm{solo},\ o = \bot,\ \ell = \top,\ s = \bot,
\mathrm{in} = [\,],\ \mathrm{out} = [\,],\ \mathrm{ev} = [\,],
T = [\,],\ M = [\,],\ A = [\,]$$

people/index.tsx:13-17 static composition. -/
def people : PartSpec := { id := "people", group := .solo, plan := .solo }

/-- Contract row of `people.card`.

$$g = G_1,\ g_{\mathrm{plan}} = G_1,\ o = 40,\ \ell = \top,\ s = \bot,
\mathrm{in} = [\texttt{vh}, \texttt{clock}, \texttt{rect:hero.exit}, \texttt{rect:people.card}, \texttt{className:data-o-stack/people.o}],\ \mathrm{out} = [\texttt{cssVar:--future-shrink/people.card}, \texttt{className:is-visible/people.card}, \texttt{className:is-shrinking/people.card}, \texttt{className:data-fw-scene/people.card}, \texttt{className:is-pain-dark/pain}, \texttt{className:data-fw-pain-dark/pain}],\ \mathrm{ev} = [\,],
T = [\texttt{people.card}, \texttt{pain}],\ M = [\,],\ A = [\,]$$

people.card/index.tsx:68 order 40 (people/shared.ts:41), callback requests its own frame (driver.ts:35,63);
reads 44-52, writes on its section (95) 55-57,73 and `is-pain-dark` and `data-fw-pain-dark` on pain 61-62. Its title
row's gap follows people.o's `data-o-stack` (card.module.css:170 `.titleWords:has([data-o-stack='true'])`, live at
width ≤ 860px, 136). -/
def peopleCard : PartSpec :=
  { id := "people.card", group := .g1, plan := .g1, order := some 40,
    inputs := [vh, clock, rect "hero.exit", rect "people.card", className "data-o-stack/people.o"],
    outputs := [cssVar "--future-shrink/people.card", className "is-visible/people.card",
      className "is-shrinking/people.card", className "data-fw-scene/people.card", className "is-pain-dark/pain",
      className "data-fw-pain-dark/pain"],
    targets := ["people.card", "pain"] }

/-- Contract row of `people.carousel`.

$$g = \mathrm{solo},\ g_{\mathrm{plan}} = \mathrm{solo},\ o = \bot,\ \ell = \top,\ s = \bot,
\mathrm{in} = [\texttt{clock}, \texttt{rect:people}],\ \mathrm{out} = [\,],\ \mathrm{ev} = [\,],
T = [\texttt{people.carousel}],\ M = [\,],\ A = [\,]$$

people.carousel/index.tsx:22 clock loop, 23-24 `watchActive` (people/shared.ts:29-37) on `closest('[data-fw="people"]')`,
the people section, rendered by people.card (people.card/index.tsx:95). -/
def peopleCarousel : PartSpec :=
  { id := "people.carousel", group := .solo, plan := .solo,
    inputs := [clock, rect "people"], targets := ["people.carousel"] }

/-- Contract row of `people.deck`.

$$g = \mathrm{solo},\ g_{\mathrm{plan}} = \mathrm{solo},\ o = 30,\ \ell = \top,\ s = \bot,
\mathrm{in} = [\texttt{vh}, \texttt{vw}, \texttt{clock}, \texttt{pointer}, \texttt{rect:people.deck}],\ \mathrm{out} = [\texttt{cssVar:--profile-scale/people.deck}, \texttt{className:data-fw-scene/people.deck}],\ \mathrm{ev} = [\texttt{scrollY}],
T = [\texttt{people.deck}],\ M = [\,],\ A = [\,]$$

people.deck/index.tsx:81 order 30, callback requests its own frame; driver.ts:86-96,130-137 own showcase height
(RUNWAY-free, fixed for a fixed vh), `--profile-scale` and shell transforms, 152 clock; index.tsx:86 `data-fw-scene`;
`goto` (driver.ts:214) is click-driven. -/
def peopleDeck : PartSpec :=
  { id := "people.deck", group := .solo, plan := .solo, order := some 30,
    inputs := [vh, vw, clock, pointer, rect "people.deck"],
    outputs := [cssVar "--profile-scale/people.deck", className "data-fw-scene/people.deck"],
    onEvent := [scrollY], targets := ["people.deck"] }

/-- Contract row of `people.o`.

$$g = G_1,\ g_{\mathrm{plan}} = \mathrm{solo},\ o = 20,\ \ell = \top,\ s = \bot,
\mathrm{in} = [\texttt{pointer}, \texttt{vw}, \texttt{vh}, \texttt{rect:people.o}, \texttt{clock}, \texttt{rect:people.card}],\ \mathrm{out} = [\texttt{className:data-o-stack/people.o}],\ \mathrm{ev} = [\,],
T = [\texttt{people.o}],\ M = [\,],\ A = [\,]$$

people.o/index.tsx:67 order 20, `place` (37-45) returns at once unless the hover preview is open; 64 observer. When
open it reads innerWidth and innerHeight (42-44) and writes the preview's left, top and width; that hover-gated write
is excluded from `outputs` because no profile hovers. It observes people.card's `#future-heading` (index.tsx:50,64);
the clock timeline (driver.ts:38-45, `STACK_DELAY` logic.ts:8) sets `data-o-stack` (index.tsx:114), which people.card's
CSS reads, so it joins G1 by I3. -/
def peopleO : PartSpec :=
  { id := "people.o", group := .g1, plan := .solo, order := some 20,
    inputs := [pointer, vw, vh, rect "people.o", clock, rect "people.card"],
    outputs := [className "data-o-stack/people.o"], targets := ["people.o"] }

/-- Contract row of `platform`.

$$g = G_2,\ g_{\mathrm{plan}} = G_2,\ o = 95,\ \ell = \top,\ s = \bot,
\mathrm{in} = [\texttt{vh}, \texttt{rect:platform}, \texttt{cssVar:--morph-fade/platform}],\ \mathrm{out} = [\texttt{cssVar:--platform-shrink/platform}, \texttt{className:is-shrinking/platform}],\ \mathrm{ev} = [\,],
T = [\texttt{platform}],\ M = [\,],\ A = [\texttt{RL}, \texttt{WS}, \texttt{WS}]$$

platform/index.tsx:27,104 order 95, `frame` reads the card rect and writes `--platform-shrink` and a class
(90-99); platform.module.css:12-13 reads `--morph-fade`. -/
def platform : PartSpec :=
  { id := "platform", group := .g2, plan := .g2, order := some 95,
    inputs := [vh, rect "platform", cssVar "--morph-fade/platform"],
    outputs := [cssVar "--platform-shrink/platform", className "is-shrinking/platform"], targets := ["platform"],
    listAccess := [readLayout, writeStyle, writeStyle] }

/-- Contract row of `platform.entries`.

$$g = G_2,\ g_{\mathrm{plan}} = \mathrm{solo},\ o = \bot,\ \ell = \top,\ s = \bot,
\mathrm{in} = [\texttt{clock}, \texttt{scenePaused}, \texttt{rect:platform.entries}],\ \mathrm{out} = [\,],\ \mathrm{ev} = [\,],
T = [\texttt{platform.entries}],\ M = [\,],\ A = [\,]$$

platform.entries/driver.ts:10 observer, 44,80 clock; rendered in platform/Visuals.tsx inside the platform section,
paused by engine.scene's `data-fw-hidden` there. -/
def platformEntries : PartSpec :=
  { id := "platform.entries", group := .g2, plan := .solo,
    inputs := [clock, scenePaused, rect "platform.entries"], targets := ["platform.entries"] }

/-- Contract row of `platform.glint`.

$$g = G_2,\ g_{\mathrm{plan}} = \mathrm{solo},\ o = \bot,\ \ell = \top,\ s = \bot,
\mathrm{in} = [\texttt{clock}, \texttt{scenePaused}, \texttt{rect:platform.glint}],\ \mathrm{out} = [\,],\ \mathrm{ev} = [\,],
T = [\texttt{platform.glint}],\ M = [\,],\ A = [\,]$$

platform.glint/driver.ts:23 clock, platform/Visuals.tsx:332 observer; paused by engine.scene. -/
def platformGlint : PartSpec :=
  { id := "platform.glint", group := .g2, plan := .solo,
    inputs := [clock, scenePaused, rect "platform.glint"], targets := ["platform.glint"] }

/-- Contract row of `platform.marquee`.

$$g = G_2,\ g_{\mathrm{plan}} = \mathrm{solo},\ o = \bot,\ \ell = \top,\ s = \bot,
\mathrm{in} = [\texttt{scenePaused}],\ \mathrm{out} = [\,],\ \mathrm{ev} = [\,],
T = [\,],\ M = [\,],\ A = [\,]$$

platform/Visuals.tsx:139 `data-marquee` CSS animation inside the platform section; paused by engine.scene. -/
def platformMarquee : PartSpec :=
  { id := "platform.marquee", group := .g2, plan := .solo, inputs := [scenePaused] }

/-- Contract row of `platform.stageBg`.

$$g = G_2,\ g_{\mathrm{plan}} = \mathrm{solo},\ o = \bot,\ \ell = \top,\ s = \bot,
\mathrm{in} = [\texttt{scenePaused}],\ \mathrm{out} = [\,],\ \mathrm{ev} = [\,],
T = [\,],\ M = [\,],\ A = [\,]$$

platform/Visuals.tsx stage background CSS animation inside the platform section; paused by engine.scene. -/
def platformStageBg : PartSpec :=
  { id := "platform.stageBg", group := .g2, plan := .solo, inputs := [scenePaused] }

/-- Contract row of `platform.sweep`.

$$g = G_2,\ g_{\mathrm{plan}} = \mathrm{solo},\ o = \bot,\ \ell = \top,\ s = \bot,
\mathrm{in} = [\texttt{scenePaused}, \texttt{rect:platform.sweep}],\ \mathrm{out} = [\,],\ \mathrm{ev} = [\,],
T = [\texttt{platform.sweep}],\ M = [\,],\ A = [\,]$$

platform/Visuals.tsx:24 own class toggle on its observer; paused by engine.scene. -/
def platformSweep : PartSpec :=
  { id := "platform.sweep", group := .g2, plan := .solo,
    inputs := [scenePaused, rect "platform.sweep"], targets := ["platform.sweep"] }

/-- The contract table: one row per directory under `apps/site/src/parts`, in directory order.

$$\mathrm{parts} = [P_1, \dots, P_{34}]$$

Every part id the site registers, once. -/
def parts : List PartSpec :=
  [commission, commissionTyping, engineScene, engineScroll, hero, heroAccent, heroCountdown, heroCue, heroDeck,
    heroExit, heroOrbit, morphColumns, morphCountdown, morphMount, morphPanel, morphTween, nav, navHitTest, navLangMenu,
    overlaysDrawer, overlaysSignup, pain, painNotes, people, peopleCard, peopleCarousel, peopleDeck, peopleO, platform,
    platformEntries, platformGlint, platformMarquee, platformStageBg, platformSweep]

/-- The table has 34 rows with pairwise distinct ids.

$$|\mathrm{parts}| = 34 \ \land\ \operatorname{Nodup}([P.\mathrm{id} \mid P \in \mathrm{parts}])$$

No part id is missing a twin row or listed twice. -/
theorem parts_ids : parts.length = 34 ∧ (parts.map (·.id)).Nodup := by decide

/-- I1, DOM-disjoint targets: neither part writes an element the other owns or writes.

$$\mathrm{I1}(P,Q) \iff T_P \cap (\{Q.\mathrm{id}\} \cup T_Q) = \emptyset \ \land\ T_Q \cap (\{P.\mathrm{id}\} \cup T_P) = \emptyset$$

Swapping one part's writes cannot touch the other's elements. -/
def i1 (P Q : PartSpec) : Bool :=
  !(P.targets.any (Q.id :: Q.targets).contains) && !(Q.targets.any (P.id :: P.targets).contains)

/-- I2, layout-local: neither part's frame writes move the other's box.

$$\mathrm{I2}(P,Q) \iff Q.\mathrm{id} \notin M_P \ \land\ P.\mathrm{id} \notin M_Q$$

Boxes are judged under a fixed viewport. -/
def i2 (P Q : PartSpec) : Bool := !(P.moves.contains Q.id) && !(Q.moves.contains P.id)

/-- A written signal changes a read one: the same signal, or a scroll write and any box read.

$$\operatorname{affects}(o,i) \iff o = i \lor (o = \mathrm{scrollY} \land \exists n:\ i = \mathrm{rect}(n))$$

A scroll write moves every viewport rect; no other signal reaches a different one. -/
def affects (o i : Signal) : Bool :=
  o == i || (o == .scrollY && match i with | .rect _ => true | _ => false)

/-- Effective frame-time outputs: the declared outputs, then a box read of every part the frame writes move.

$$\operatorname{effOut}(P) = \mathrm{out}_P \mathbin{+\!\!+} [\mathrm{rect}(m) \mid m \in M_P]$$

`onEvent` signals are not part of it. -/
def effOut (P : PartSpec) : List Signal := P.outputs ++ P.moves.map Signal.rect

/-- I3, no signal flow: no effective frame-time output of one part affects an input of the other.

$$\mathrm{I3}(P,Q) \iff \bigl(\forall o \in \operatorname{effOut}(P),\ \forall i \in \mathrm{in}_Q:\ \lnot\operatorname{affects}(o,i)\bigr)
\land \bigl(\forall o \in \operatorname{effOut}(Q),\ \forall i \in \mathrm{in}_P:\ \lnot\operatorname{affects}(o,i)\bigr)$$

What one part writes per frame, the other never reads, directly or through a scroll-moved box. -/
def i3 (P Q : PartSpec) : Bool :=
  !((effOut P).any fun o => Q.inputs.any (affects o)) && !((effOut Q).any fun o => P.inputs.any (affects o))

/-- Running two inline access lists back to back forces exactly as many style and layout updates as running each from
a clean state.

$$\operatorname{additive}(a,b) \iff \forall \rho \in \{\rho_S, \rho_L\}:\ \operatorname{forced}_\rho(\bot, a \mathbin{+\!\!+} b) = \operatorname{forced}_\rho(\bot, a) + \operatorname{forced}_\rho(\bot, b)$$

False exactly when `a` leaves work dirty that a read in `b` must flush. -/
def additive (a b : List Access) : Bool :=
  forced styleRole false (a ++ b) == forced styleRole false a + forced styleRole false b &&
  forced layoutRole false (a ++ b) == forced layoutRole false a + forced layoutRole false b

/-- I4, no forced-update chain in the ordered scroll list and no shared schedule: when both parts are registered,
their inline lists are additive in list order; a part whose variant changes the schedule (`schedules`) couples to
every registered part.

$$\mathrm{I4}(P,Q) \iff \lnot(s_P \land o_Q \ne \bot) \land \lnot(s_Q \land o_P \ne \bot) \land
\begin{cases} \operatorname{additive}(A_P, A_Q) & o_P = p,\ o_Q = q,\ p \le q \\
\operatorname{additive}(A_Q, A_P) & o_P = p,\ o_Q = q,\ p > q \\ \top & o_P = \bot \lor o_Q = \bot \end{cases}$$

Only the pair is checked, under the faithful engine variant; clock-subscriber order within the frame is not modeled. -/
def i4 (P Q : PartSpec) : Bool :=
  !(P.schedules && Q.order.isSome) && !(Q.schedules && P.order.isSome) &&
    match P.order, Q.order with
    | some p, some q => if p ≤ q then additive P.listAccess Q.listAccess else additive Q.listAccess P.listAccess
    | _, _ => true

/-- Decision procedure for `Independent`. $$\operatorname{independent}(P,Q) \iff \mathrm{I1} \land \mathrm{I2} \land \mathrm{I3} \land \mathrm{I4}$$
I5 (overlap compositing) is a recorded premise, not part of the decision. -/
def independent (P Q : PartSpec) : Bool := i1 P Q && i2 P Q && i3 P Q && i4 P Q

/-- Two parts are independent when premises I1-I4 hold for the pair.

$$\operatorname{Independent}(P,Q) \iff \mathrm{I1}(P,Q) \land \mathrm{I2}(P,Q) \land \mathrm{I3}(P,Q) \land \mathrm{I4}(P,Q)$$

Swapping either part's variant leaves the other's inputs, elements and forced updates unchanged (given I5). -/
abbrev Independent (P Q : PartSpec) : Prop := independent P Q = true

/-- Group key: the group name, or the part id for a solo part.

$$\kappa(P) = \begin{cases} P.\mathrm{id} & g_P = \mathrm{solo} \\ \operatorname{name}(g_P) & \text{otherwise} \end{cases}$$

Two parts share a key exactly when they must be integrated together. -/
def groupKey (P : PartSpec) : String :=
  match P.group with
  | .solo => P.id
  | g => g.name

/-- A part is page-level when its variant reschedules the scroll list or it writes the scroll position. Derived from
the row, never set by hand.

$$\operatorname{page}(P) \iff s_P \lor \mathrm{scrollY} \in \mathrm{out}_P$$

Its variants are measured only on whole-page runs. -/
def pageLevel (P : PartSpec) : Bool := P.schedules || P.outputs.contains .scrollY

/-- Parts that are not page-level and have different group keys are independent.

$$\forall P \in \mathrm{parts},\ \forall Q \in \mathrm{parts}:\ \lnot\operatorname{page}(P) \to \lnot\operatorname{page}(Q) \to
\kappa(P) \ne \kappa(Q) \to \operatorname{Independent}(P,Q)$$

Each group can be built, optimized and measured on its own. Accepted limits (judge against these, do not reopen
them): `outputs` list only signals another part can read (own-element aria, viewBox and tabIndex writes excluded); I4
is pairwise with no clock-subscriber order; event-only writes are excluded (overlays' body overflow); a box move is
hand-listed in `moves` (gate PL1 witnesses it; part-io-lint checks code against declared writes, not which boxes a
write moves); `vw` and `vh` have no writer; I5 layerization is a recorded premise; dead selectors under hashed
CSS-module names are recorded in the row docstrings. Certified relative to the declared rows; row completeness is an
unverified premise (contract-rows-from-code / part-io-lint). Known gaps, recorded as data and not patched: pain.notes'
`cardSelector` (pain.notes/index.tsx:40) and nav.hitTest's `EXCLUDE_SELECTOR` (nav.hitTest/logic.ts:19) match no
element, because CSS-module class names are renamed (apps/site/scripts/build.mjs:41); these are faithfulness findings
for those two parts, and the rows declare the code's intended selectors. -/
theorem groups_partition :
    ∀ P ∈ parts, ∀ Q ∈ parts, ¬ pageLevel P → ¬ pageLevel Q → groupKey P ≠ groupKey Q → Independent P Q := by
  decide

/-- A G4 part is coupled to every registered part, so it is measured only on whole-page runs.

$$\forall P \in \mathrm{parts},\ \forall Q \in \mathrm{parts}:\ g_P = G_4 \to o_Q \ne \bot \to \lnot\operatorname{Independent}(P,Q)$$

engine.scroll's variant reschedules every scroll-list callback. -/
theorem g4_couples : ∀ P ∈ parts, ∀ Q ∈ parts, P.group = .g4 → Q.order.isSome → ¬ Independent P Q := by decide

/-- A part that writes the scroll position is coupled to every part that reads it or a box.

$$\forall P \in \mathrm{parts}:\ \mathrm{scrollY} \in \mathrm{out}_P \to \forall Q \in \mathrm{parts}:\
(\exists i \in \mathrm{in}_Q:\ \operatorname{affects}(\mathrm{scrollY}, i)) \to \lnot\operatorname{Independent}(P,Q)$$

morph.tween's pin moves every rect any other part reads. -/
theorem scroll_writer_couples :
    ∀ P ∈ parts, .scrollY ∈ P.outputs → ∀ Q ∈ parts, Q.inputs.any (affects .scrollY) → ¬ Independent P Q := by
  decide

/-- morph.tween is the only part that writes the scroll position at frame time.

$$[P.\mathrm{id} \mid P \in \mathrm{parts},\ \mathrm{scrollY} \in \mathrm{out}_P] = [\texttt{morph.tween}]$$

The click `scrollTo`s of hero.cue and people.deck are event-only. -/
theorem scroll_writers : (parts.filter (·.outputs.contains .scrollY)).map (·.id) = ["morph.tween"] := by decide

/-- No part outside the page level writes a signal that affects a page-level part's input.

$$\forall P \in \mathrm{parts}:\ \operatorname{page}(P) \to \forall Q \in \mathrm{parts}:\ \lnot\operatorname{page}(Q) \to
\lnot\exists o \in \operatorname{effOut}(Q),\ \exists i \in \mathrm{in}_P:\ \operatorname{affects}(o,i)$$

Page-level parts read only the environment, so a group's variant cannot change them. -/
theorem pagelevel_env_only :
    ∀ P ∈ parts, pageLevel P → ∀ Q ∈ parts, ¬ pageLevel Q → ¬ ∃ o ∈ effOut Q, ∃ i ∈ P.inputs, affects o i := by
  decide

/-- A part is in G4 exactly when its variant reschedules the scroll list.

$$\forall P \in \mathrm{parts}:\ g_P = G_4 \iff s_P$$

The hand-set group cannot contradict the row's `schedules` flag. -/
theorem g4_iff : ∀ P ∈ parts, (P.group == .g4) = P.schedules := by decide

/-- The `layoutLocal` flag is exactly "moves no other part".

$$\forall P \in \mathrm{parts}:\ \ell_P \iff M_P = [\,]$$

The flag cannot drift from the `moves` list. -/
theorem layoutLocal_iff : ∀ P ∈ parts, P.layoutLocal = P.moves.isEmpty := by decide

/-- Members of a group, in table order. $$\operatorname{members}(g) = [P.\mathrm{id} \mid P \in \mathrm{parts},\ g_P = g]$$
The empty list when no row is in the group. -/
def members (g : Group) : List String := (parts.filter (·.group == g)).map (·.id)

/-- Parts whose group the code moved away from the plan's. $$\operatorname{moved} = [P.\mathrm{id} \mid P \in \mathrm{parts},\ g_P \ne g_{\mathrm{plan},P}]$$
The rows the report lists as code-wins changes. -/
def moved : List String := (parts.filter (fun P => P.group != P.plan)).map (·.id)

/-- The code-wins moves and the empty groups, as decided by the table.

$$\operatorname{moved} = [\texttt{commission}, \texttt{commission.typing}, \texttt{engine.scene}, \texttt{hero.accent},
\texttt{hero.cue}, \texttt{hero.deck}, \texttt{hero.orbit}, \texttt{morph.columns}, \texttt{morph.countdown},
\texttt{morph.mount}, \texttt{morph.panel}, \texttt{nav}, \texttt{nav.hitTest}, \texttt{nav.langMenu},
\texttt{pain.notes}, \texttt{people.o}, \texttt{platform.entries}, \texttt{platform.glint}, \texttt{platform.marquee},
\texttt{platform.stageBg}, \texttt{platform.sweep}] \land \operatorname{members}(G_3) = \operatorname{members}(G_5) = [\,]$$

Twenty-one rows differ from the plan; G3 and G5 have no members. -/
theorem moved_eq :
    moved = ["commission", "commission.typing", "engine.scene", "hero.accent", "hero.cue", "hero.deck", "hero.orbit",
      "morph.columns", "morph.countdown", "morph.mount", "morph.panel", "nav", "nav.hitTest", "nav.langMenu",
      "pain.notes", "people.o", "platform.entries", "platform.glint", "platform.marquee", "platform.stageBg", "platform.sweep"] ∧
    members .g3 = [] ∧ members .g5 = [] := by decide

/-- Measurement profiles present in `packages/measure-chromium/profiles` (file stem = profile id); there is no `push`
profile. $$\mathrm{profiles} = [\texttt{engine-premise-cr}, \texttt{fixture-rest}, \texttt{swipe-touch-v1}, \texttt{swipe-v1}, \texttt{swipe-wheel-v1}]$$
The ContractsGolden check fails when one of the used ones is missing on disk. -/
def profiles : List String := ["engine-premise-cr", "fixture-rest", "swipe-touch-v1", "swipe-v1", "swipe-wheel-v1"]

/-- Signals that move with scroll: `scrollY` and every frame-time output of a registered part.

$$\Sigma_{\mathrm{scroll}} = [\mathrm{scrollY}] \mathbin{+\!\!+} [\sigma \mid P \in \mathrm{parts},\ o_P \ne \bot,\ \sigma \in \mathrm{out}_P]$$

What a part reads to depend on scroll position. -/
def scrollSignals : List Signal := .scrollY :: (parts.filter (·.order.isSome)).flatMap (·.outputs)

/-- A part is scroll-driven when it reads a rect or a scroll signal.

$$\operatorname{scroll}(P) \iff \exists \sigma \in \mathrm{in}_P:\ \sigma = \mathrm{rect}(n) \text{ for some } n \lor \sigma \in \Sigma_{\mathrm{scroll}}$$

Its work varies along a swipe. -/
def scrollDriven (P : PartSpec) : Bool :=
  P.inputs.any fun s => (match s with | .rect _ => true | _ => false) || scrollSignals.contains s

/-- A part is morph-driven when it is in the morph group G2.

$$\operatorname{morph}(P) \iff g_P = G_2$$

Its work needs wheel or touch input, which the scroll-jacked morph (morph.tween/driver.ts:89-91) listens to. -/
def morphDriven (P : PartSpec) : Bool := P.group == .g2

/-- Profiles a part is measured under: wheel and touch swipes when morph-driven, the scripted swipe when
scroll-driven, otherwise the rest fixture (the plan's `push` maps to the wheel and touch swipes).

$$S(P) = \begin{cases} [\texttt{fixture-rest}] & \lnot\operatorname{morph}(P) \land \lnot\operatorname{scroll}(P) \\
[\texttt{swipe-wheel-v1}, \texttt{swipe-touch-v1}]_{\operatorname{morph}(P)} \mathbin{+\!\!+} [\texttt{swipe-v1}]_{\operatorname{scroll}(P)} & \text{otherwise} \end{cases}$$

where $[x]_b$ is $x$ when $b$ holds and $[\,]$ otherwise. Certified relative to the declared rows; row completeness
is an unverified premise (contract-rows-from-code / part-io-lint). -/
def scenariosFor (P : PartSpec) : List String :=
  let xs := (if morphDriven P then ["swipe-wheel-v1", "swipe-touch-v1"] else []) ++
    (if scrollDriven P then ["swipe-v1"] else [])
  if xs.isEmpty then ["fixture-rest"] else xs

/-- Every profile a part is assigned exists.

$$\forall P \in \mathrm{parts},\ \forall s \in S(P):\ s \in \mathrm{profiles}$$

No scenario names a profile the repo lacks. -/
theorem scenarios_known : ∀ P ∈ parts, ∀ s ∈ scenariosFor P, s ∈ profiles := by decide

/-- JSON string literal. $$\operatorname{jstr}(s) = \texttt{"} \mathbin{+\!\!+} \operatorname{esc}(s) \mathbin{+\!\!+} \texttt{"}$$
`esc` escapes only backslash and double quote (no control characters occur in the table). -/
def jstr (s : String) : String := "\"" ++ ((s.replace "\\" "\\\\").replace "\"" "\\\"") ++ "\""

/-- JSON array of rendered items. $$\operatorname{jarr}([x_1,\dots,x_n]) = \texttt{[}x_1\texttt{,}\dots\texttt{,}x_n\texttt{]}$$
`[]` for the empty list. -/
def jarr (xs : List String) : String := "[" ++ ",".intercalate xs ++ "]"

/-- Wire form of a signal. $$\operatorname{wire}(\mathrm{cssVar}(n)) = \texttt{cssVar:}n,\ \operatorname{wire}(\mathrm{className}(n)) = \texttt{className:}n,\ \operatorname{wire}(\mathrm{rect}(n)) = \texttt{rect:}n$$
Nullary signals render as their constructor name. -/
def Signal.wire : Signal → String
  | .scrollY => "scrollY" | .vw => "vw" | .vh => "vh" | .clock => "clock" | .pointer => "pointer"
  | .morphPhase => "morphPhase" | .scenePaused => "scenePaused"
  | .cssVar n => "cssVar:" ++ n | .className n => "className:" ++ n | .rect n => "rect:" ++ n

/-- Wire form of an access. $$\mathrm{RS}, \mathrm{RL}, \mathrm{WS}, \mathrm{WL}$$ The two-letter codes of `Access`. -/
def accessWire : Access → String
  | .readStyle => "RS" | .readLayout => "RL" | .writeStyle => "WS" | .writeLayout => "WL"

/-- A contract signal as the footprint spells it: `scenePaused` is `data-fw-hidden` on the platform, `morphPhase`
`data-fw-morph` on the nav.

$$\operatorname{fw}(\mathrm{scenePaused}) = \texttt{className:data-fw-hidden/platform},\
\operatorname{fw}(\mathrm{morphPhase}) = \texttt{className:data-fw-morph/nav},\ \operatorname{fw}(\sigma) =
\operatorname{wire}(\sigma) \text{ otherwise}$$

The two named signals are attributes the code writes. -/
def Signal.fw : Signal → String
  | .scenePaused => "className:data-fw-hidden/platform"
  | .morphPhase => "className:data-fw-morph/nav"
  | s => s.wire

/-- Extracted accesses of part `id`. $$\operatorname{code}(p) = [a \in \mathrm{accesses} \mid a.\mathrm{part} = p]$$
Empty for an id with no code. -/
def code (id : String) : List Footprint.Access := FootprintData.accesses.filter (·.part == id)

/-- Environment and box wires: a read of these is an input whoever writes them.
$$\operatorname{env}(w) \iff w \in [\texttt{vw}, \texttt{vh}, \texttt{scrollY}, \texttt{clock}, \texttt{pointer}] \lor
\texttt{rect:} \sqsubseteq w$$ Every other wire is an input only when another part writes it. -/
def envWire (w : String) : Bool := ["vw", "vh", "scrollY", "clock", "pointer"].contains w || w.startsWith "rect:"

/-- Wires the parts other than `id` write at frame or event time, first occurrence kept.
$$W_{\ne p} = \operatorname{dedup}[w \mid a \in \mathrm{accesses},\ a.\mathrm{part} \ne p,\ \phi(a.\mathrm{ctx}) \in
\{\mathrm{frame}, \mathrm{event}\},\ w \in \operatorname{writes}(a)]$$
Mount, hover, resize and cleanup writes set no cross-part signal. -/
def othersWrite (id : String) : List String :=
  ((FootprintData.accesses.filter fun a =>
    a.part != id && (Footprint.phase a.ctx == .frame || Footprint.phase a.ctx == .event)).flatMap
      Footprint.writes).eraseDups

/-- Wires the parts other than `id` read, first occurrence kept.
$$R_{\ne p} = \operatorname{dedup}[r \mid a \in \mathrm{accesses},\ a.\mathrm{part} \ne p,\ r \in \operatorname{reads}(a)]$$
`reads` already drops cleanup. -/
def othersRead (id : String) : List String :=
  ((FootprintData.accesses.filter (·.part != id)).flatMap Footprint.reads).eraseDups

/-- Code inputs of part `id`: its environment and box reads, and each wire another part writes that one of its reads
names.

$$\operatorname{in}_{\mathrm{code}}(p) = \operatorname{dedup}\big[x \mid r \in \operatorname{dedup}(\operatorname{reads}
(\operatorname{code}(p))),\ x \in (\text{if } \operatorname{env}(r) \text{ then } [r] \text{ else }
[w \in W_{\ne p} \mid \operatorname{same}(r, w)])\big]$$

A read of the part's own classes or variables is not an input. -/
def codeInputs (id : String) : List String :=
  let ws := othersWrite id
  (((code id).flatMap Footprint.reads).eraseDups.flatMap fun r =>
    if envWire r then [r] else ws.filter (Footprint.same r ·)).eraseDups

/-- Cross-part writes of part `id` in phase `ph`: its writes there that are `scrollY` or that another part reads.

$$\operatorname{out}_{\mathrm{code}}(p, \phi_0) = [w \in \operatorname{dedup}[w \mid a \in \operatorname{code}(p),\
\phi(a.\mathrm{ctx}) = \phi_0,\ w \in \operatorname{writes}(a)] \mid w = \texttt{scrollY} \lor \exists r \in R_{\ne p}:
\operatorname{same}(r, w)]$$

`scrollY` moves every box, so it counts without a named reader. -/
def crossWrites (id : String) (ph : Footprint.Phase) : List String :=
  let rs := othersRead id
  ((((code id).filter (Footprint.phase ·.ctx == ph)).flatMap Footprint.writes).eraseDups).filter fun w =>
    w == "scrollY" || rs.any (Footprint.same · w)

/-- Owners of the elements part `id` writes at frame time, when the owner is a part id.

$$T_{\mathrm{code}}(p) = \operatorname{dedup}[a.\mathrm{owner} \mid a \in \operatorname{code}(p),\ \phi(a.\mathrm{ctx})
= \mathrm{frame},\ \operatorname{isWrite}(a.\mathrm{op}),\ a.\mathrm{op} \ne \mathrm{scroll},\ a.\mathrm{owner} \in
\mathrm{ids}]$$

`document`, `?` and parent owners are left out. -/
def codeTargets (id : String) : List String :=
  (((code id).filter fun a => Footprint.phase a.ctx == .frame && a.op.isWrite && a.op != .scroll &&
    parts.any (·.id == a.owner)).map (·.owner)).eraseDups

/-- Scroll-list orders part `id` registers with. $$O_{\mathrm{code}}(p) = \operatorname{dedup}[n \mid a \in
\operatorname{code}(p),\ a.\mathrm{op} = \mathrm{register},\ n = \operatorname{toNat}(a.\mathrm{name})]$$
A non-numeric name is left out. -/
def codeOrder (id : String) : List Nat :=
  (((code id).filter (·.op == .register)).filterMap (·.name.toNat?)).eraseDups

/-- Code-side wires missing from a row list, and row wires the code never touches.

$$\operatorname{gap}(C, R, A) = ([c \in C \mid \nexists r \in R: \operatorname{same}(c, r)],\ [r \in R \mid \nexists a
\in A: \operatorname{same}(a, r)])$$

$C$ the code's cross-part wires, $R$ the row's, $A$ every wire the code reads or writes on that side. -/
def gap (c r a : List String) : List String × List String :=
  (c.filter fun x => !r.any (Footprint.same x ·), r.filter fun y => !a.any (Footprint.same · y))

/-- One part's diff as a JSON line: inputs, outputs, `onEvent` and targets as missing-from-row and
not-in-code lists, and the row order against the code orders.

$$\operatorname{diff}(P) = \{\mathrm{id},\ \mathrm{in}: \operatorname{gap}(\operatorname{in}_{\mathrm{code}},
\operatorname{fw}(\mathrm{in}_P), \operatorname{reads}),\ \mathrm{out}: \operatorname{gap}(\operatorname{out}_{\mathrm{code}}
(\mathrm{frame}), \operatorname{fw}(\mathrm{out}_P), \operatorname{writes}),\ \mathrm{ev}: \operatorname{gap}
(\operatorname{out}_{\mathrm{code}}(\mathrm{event}), \operatorname{fw}(\mathrm{ev}_P), \operatorname{writes}),\ T:
\operatorname{gap}(T_{\mathrm{code}}, T_P, T_{\mathrm{code}}),\ o: (o_P, O_{\mathrm{code}})\}$$

`reads` and `writes` range over all of the part's accesses, any phase. -/
def diffJson (P : PartSpec) : String :=
  let rs := ((code P.id).flatMap Footprint.reads).eraseDups
  let ws := ((code P.id).flatMap Footprint.writes).eraseDups
  let ct := codeTargets P.id
  let pair (g : List String × List String) : String :=
    "{\"missing\":" ++ jarr (g.1.map jstr) ++ ",\"extra\":" ++ jarr (g.2.map jstr) ++ "}"
  "{\"id\":" ++ jstr P.id ++
    ",\"inputs\":" ++ pair (gap (codeInputs P.id) (P.inputs.map Signal.fw) rs) ++
    ",\"outputs\":" ++ pair (gap (crossWrites P.id .frame) (P.outputs.map Signal.fw) ws) ++
    ",\"onEvent\":" ++ pair (gap (crossWrites P.id .event) (P.onEvent.map Signal.fw) ws) ++
    ",\"targets\":" ++ pair (gap ct P.targets ct) ++
    ",\"order\":{\"row\":" ++ (match P.order with | some o => toString o | none => "null") ++
    ",\"code\":" ++ jarr ((codeOrder P.id).map toString) ++ "}}"

/-- A (kind, name) wire pair as a contract signal, first matching case.

$$\operatorname{sig}(k, n) = \begin{cases} \sigma & k \in \{\texttt{scrollY}, \texttt{vw}, \texttt{vh}, \texttt{clock},
\texttt{pointer}\},\ \sigma \text{ the signal of that name} \\
\mathrm{scenePaused} & (k, n) = (\texttt{className}, \texttt{data-fw-hidden/platform}) \\
\mathrm{morphPhase} & (k, n) = (\texttt{className}, \texttt{data-fw-morph/nav}) \\
\mathrm{cssVar}(n) & k = \texttt{cssVar} \\ \mathrm{rect}(n) & k = \texttt{rect} \\
\mathrm{className}(n) & \text{otherwise} \end{cases}$$

The inverse of `Signal.fw` on the wires the footprint produces; an unknown kind becomes a class name. -/
def Signal.ofWire : String × String → Signal
  | ("scrollY", _) => .scrollY | ("vw", _) => .vw | ("vh", _) => .vh | ("clock", _) => .clock
  | ("pointer", _) => .pointer
  | ("className", "data-fw-hidden/platform") => .scenePaused
  | ("className", "data-fw-morph/nav") => .morphPhase
  | ("cssVar", n) => .cssVar n | ("rect", n) => .rect n
  | (_, n) => .className n

/-- The code row of part `id`, each wire split into a (kind, name) pair.

$$r(p) = \big(p,\ \operatorname{kind}^*(\operatorname{in}_{\mathrm{code}}(p)),\ \operatorname{kind}^*(\operatorname{out}_{\mathrm{code}}
(p, \mathrm{frame})),\ \operatorname{kind}^*(\operatorname{out}_{\mathrm{code}}(p, \mathrm{event})),\ T_{\mathrm{code}}(p),\
O_{\mathrm{code}}(p)\big)$$

`kind*` maps `splitKind` over a list. -/
def codeRowOf (id : String) : Footprint.Row :=
  ⟨id, (codeInputs id).map Footprint.splitKind, (crossWrites id .frame).map Footprint.splitKind,
    (crossWrites id .event).map Footprint.splitKind, codeTargets id, codeOrder id⟩

/-- Append the items of `ys` that `xs` lacks, first occurrence kept.
$$xs \uplus ys = xs \mathbin{+\!\!+} \operatorname{dedup}[y \in ys \mid y \notin xs]$$ `xs` is kept as it is. -/
def addNew {α : Type} [BEq α] (xs ys : List α) : List α := xs ++ (ys.filter (!xs.contains ·)).eraseDups

/-- Row `P` widened by the first code row in `rs` with its id: its inputs, outputs, `onEvent` and targets gain each
code item they lack; every other field stays declared.

$$\operatorname{wide}_{rs}(P) = \begin{cases} P[\mathrm{in} := \mathrm{in}_P \uplus \operatorname{sig}^*(r.\mathrm{in}),\
\mathrm{out} := \mathrm{out}_P \uplus \operatorname{sig}^*(r.\mathrm{out}),\ \mathrm{ev} := \mathrm{ev}_P \uplus
\operatorname{sig}^*(r.\mathrm{ev}),\ T := T_P \uplus r.T] & r \text{ the first } r \in rs \text{ with } r.\mathrm{id} =
P.\mathrm{id} \\ P & \text{no } r \in rs \text{ has } r.\mathrm{id} = P.\mathrm{id} \end{cases}$$

Widening only adds signals and targets. -/
def widen (rs : List Footprint.Row) (P : PartSpec) : PartSpec :=
  match rs.find? (·.id == P.id) with
  | none => P
  | some r =>
    { P with inputs := addNew P.inputs (r.inputs.map Signal.ofWire),
             outputs := addNew P.outputs (r.outputs.map Signal.ofWire),
             onEvent := addNew P.onEvent (r.onEvent.map Signal.ofWire),
             targets := addNew P.targets r.targets }

/-- `P'` widens `P`: same id, moves and scroll-list fields, and every input, output and target of `P` is one of `P'`.

$$P' \sqsupseteq P \iff P'.\mathrm{id} = P.\mathrm{id} \land M_{P'} = M_P \land o_{P'} = o_P \land A_{P'} = A_P \land
s_{P'} = s_P \land \mathrm{in}_P \subseteq \mathrm{in}_{P'} \land \mathrm{out}_P \subseteq \mathrm{out}_{P'} \land T_P
\subseteq T_{P'}$$

$\subseteq$ is list membership; `onEvent`, groups and `layoutLocal` are unconstrained. -/
structure Widens (P' P : PartSpec) : Prop where
  id : P'.id = P.id
  moves : P'.moves = P.moves
  order : P'.order = P.order
  listAccess : P'.listAccess = P.listAccess
  schedules : P'.schedules = P.schedules
  inputs : ∀ s ∈ P.inputs, s ∈ P'.inputs
  outputs : ∀ s ∈ P.outputs, s ∈ P'.outputs
  targets : ∀ t ∈ P.targets, t ∈ P'.targets

/-- Widening by code rows widens. $$\forall rs,\ \forall P:\ \operatorname{wide}_{rs}(P) \sqsupseteq P$$
`addNew` keeps the declared list as a prefix. -/
theorem widen_widens (rs : List Footprint.Row) (P : PartSpec) : Widens (widen rs P) P := by
  unfold widen
  split
  · exact ⟨rfl, rfl, rfl, rfl, rfl, fun _ h => h, fun _ h => h, fun _ h => h⟩
  · exact ⟨rfl, rfl, rfl, rfl, rfl, fun _ h => List.mem_append_left _ h, fun _ h => List.mem_append_left _ h,
      fun _ h => List.mem_append_left _ h⟩

/-- Independence survives narrowing: parts independent after widening were independent before.

$$\forall P, Q, P', Q':\ P' \sqsupseteq P \to Q' \sqsupseteq Q \to \operatorname{Independent}(P', Q') \to
\operatorname{Independent}(P, Q)$$

More inputs, outputs or targets can only add a conflict. -/
theorem independent_antitone {P Q P' Q' : PartSpec} (hP : Widens P' P) (hQ : Widens Q' Q)
    (h : Independent P' Q') : Independent P Q := by
  simp only [Independent, independent, i1, i2, i3, i4, effOut, Bool.and_eq_true, Bool.not_eq_true',
    List.any_eq_false, List.contains_iff_mem, List.mem_cons, List.mem_append, List.mem_map] at h ⊢
  rw [hP.id, hQ.id, hP.moves, hQ.moves, hP.order, hQ.order, hP.listAccess, hQ.listAccess, hP.schedules,
    hQ.schedules] at h
  obtain ⟨⟨⟨⟨h1a, h1b⟩, h2⟩, h3a, h3b⟩, h4⟩ := h
  refine ⟨⟨⟨⟨fun t ht hm => h1a t (hP.targets t ht) ?_, fun t ht hm => h1b t (hQ.targets t ht) ?_⟩, h2⟩,
    fun o ho hi => h3a o (ho.imp (hP.outputs o) id) ?_, fun o ho hi => h3b o (ho.imp (hQ.outputs o) id) ?_⟩, h4⟩
  · exact hm.imp id (hQ.targets t)
  · exact hm.imp id (hP.targets t)
  · obtain ⟨i, hi, ha⟩ := List.any_eq_true.mp hi
    exact List.any_eq_true.mpr ⟨i, hQ.inputs i hi, ha⟩
  · obtain ⟨i, hi, ha⟩ := List.any_eq_true.mp hi
    exact List.any_eq_true.mpr ⟨i, hP.inputs i hi, ha⟩

/-- The table widened by the generated code rows.
$$\mathrm{parts}_{\mathrm{code}} = [\operatorname{wide}_{\mathrm{rows}}(P) \mid P \in \mathrm{parts}]$$
Same ids, order, groups and scroll-list fields as `parts`. -/
def codeParts : List PartSpec := parts.map (widen FootprintRows.rows)

/-- For each part of `ps`, the other parts of `ps` it is not independent of.
$$\operatorname{adj}(ps) = [(P.\mathrm{id}, [Q.\mathrm{id} \mid Q \in ps,\ Q.\mathrm{id} \ne P.\mathrm{id},\
\lnot\operatorname{independent}(P,Q)]) \mid P \in ps]$$
Ids in `ps` order. -/
def adjacency (ps : List PartSpec) : List (String × List String) :=
  ps.map fun P => (P.id, (ps.filter fun Q => Q.id != P.id && !independent P Q).map (·.id))

/-- Coupling components of the parts of `ps` that are not page-level, in `ps` order of their first member.

$$\begin{aligned} N &= [P \in ps \mid \lnot\operatorname{page}(P)],\quad \operatorname{step}(s) = [Q.\mathrm{id} \mid Q \in N,\
Q.\mathrm{id} \in s \lor \exists m \in s:\ Q.\mathrm{id} \in \operatorname{adj}(N)(m)] \\ \operatorname{comp}(ps) &=
\operatorname{foldl}\big(\lambda\,C\,P.\ \text{if } \exists c \in C:\ P.\mathrm{id} \in c \text{ then } C \text{ else }
C \mathbin{+\!\!+} [\operatorname{step}^{|N|}([P.\mathrm{id}])],\ [\,],\ N\big) \end{aligned}$$

$\operatorname{adj}(N)(m)$ is the list paired with the first entry for $m$, `[]` when there is none. -/
def components (ps : List PartSpec) : List (List String) :=
  let ns := ps.filter (!pageLevel ·)
  let adj := adjacency ns
  let step (s : List String) : List String :=
    (ns.filter fun Q => s.contains Q.id || s.any fun m => ((adj.lookup m).getD []).contains Q.id).map (·.id)
  ns.foldl (fun acc P => if acc.any (·.contains P.id) then acc else acc ++ [Nat.repeat step ns.length [P.id]]) []

/-- Text of `lean/Fw/Parts/FootprintRows.lean`: the code row of every contract row and the components of the table
widened by them.
$$\operatorname{rowsFile} = \operatorname{lean}\big([r(P.\mathrm{id}) \mid P \in \mathrm{parts}],\
\operatorname{comp}([\operatorname{wide}_{R}(P) \mid P \in \mathrm{parts}])\big),\quad R = [r(P.\mathrm{id}) \mid P \in
\mathrm{parts}]$$
One row and one group per line, newline-terminated. -/
def rowsText (_ : Unit := ()) : String :=
  let rs := parts.map (codeRowOf ·.id)
  let wl (ws : List (String × String)) : String :=
    "[" ++ ", ".intercalate (ws.map fun w => "(" ++ jstr w.1 ++ ", " ++ jstr w.2 ++ ")") ++ "]"
  let sl (xs : List String) : String := "[" ++ ", ".intercalate (xs.map jstr) ++ "]"
  let row (r : Footprint.Row) : String :=
    "  ⟨" ++ jstr r.id ++ ", " ++ wl r.inputs ++ ", " ++ wl r.outputs ++ ", " ++ wl r.onEvent ++ ", " ++
      sl r.targets ++ ", [" ++ ", ".intercalate (r.order.map toString) ++ "]⟩"
  "-- GENERATED by lake env lean --run scripts/ContractsGolden.lean --rows from Fw.Parts.FootprintData: do not edit by hand\n" ++
  "import Fw.Parts.Footprint\n\n" ++
  "namespace Fw.Parts.FootprintRows\nopen Fw.Parts.Footprint\n\n" ++
  "/-- Code rows (`Fw.Parts.Contract.codeRowOf`), one per contract row in table order. -/\n" ++
  "def rows : List Row := [\n" ++ ",\n".intercalate (rs.map row) ++ "]\n\n" ++
  "/-- Groups (`Fw.Parts.Contract.components`) of the table widened by `rows`; page-level parts are in none. -/\n" ++
  "def groups : List (List String) := [\n" ++ ",\n".intercalate (((components (parts.map (widen rs))).map fun g =>
    "  " ++ sl g)) ++ "]\n\nend Fw.Parts.FootprintRows\n"

/-- Group key on the widened table: the first member of the first generated group holding the part, else its id.
$$\kappa_{\mathrm{code}}(P) = \begin{cases} \operatorname{head}(g) & g \text{ the first } g \in \mathrm{groups} \text{
with } P.\mathrm{id} \in g \\ P.\mathrm{id} & \text{no group holds } P.\mathrm{id} \end{cases}$$
A page-level part keys as itself. -/
def codeKey (P : PartSpec) : String :=
  ((FootprintRows.groups.find? (·.contains P.id)).bind (·.head?)).getD P.id

/-- The generated rows are the contract rows' ids in table order, and each code order list is the row's order.

$$[r.\mathrm{id} \mid r \in \mathrm{rows}] = [P.\mathrm{id} \mid P \in \mathrm{parts}] \ \land\ \forall P \in
\mathrm{parts},\ \forall r \in \mathrm{rows}:\ r.\mathrm{id} = P.\mathrm{id} \to r.O = (o_P = \bot\ ?\ [\,] :
[o_P])$$

Every row has a code row; no part registers at an order other than its declared one. -/
theorem rows_ids_order : FootprintRows.rows.map (·.id) = parts.map (·.id) ∧
    ∀ P ∈ parts, ∀ r ∈ FootprintRows.rows, r.id = P.id → r.order = P.order.toList := by
  decide

/-- Parts in different re-decided groups are independent on the widened table.

$$\forall P \in \mathrm{parts}_{\mathrm{code}},\ \forall Q \in \mathrm{parts}_{\mathrm{code}}:\ \lnot\operatorname{page}(P)
\to \lnot\operatorname{page}(Q) \to \kappa_{\mathrm{code}}(P) \ne \kappa_{\mathrm{code}}(Q) \to
\operatorname{Independent}(P,Q)$$

The groups are a lower bound on coupling: they hold against the declared rows and every input, output and target
the extractor resolved, and three reads couple nothing. A box read of an unresolved element (`rect:?`) matches no box
write; it is in the rows of commission, nav, nav.hitTest and overlays.signup (and of people.deck, which is page-level).
Read conservatively, it couples those four with hero.accent (which moves hero) and so merges the six hero parts with
them; `code_groups_rect_open` shows the groups here already hold all of them together. A hit test
(`elementFromPoint`) and a computed-style read (`getComputedStyle`) read no wire at all. -/
theorem code_groups_partition :
    ∀ P ∈ codeParts, ∀ Q ∈ codeParts, ¬ pageLevel P → ¬ pageLevel Q → codeKey P ≠ codeKey Q → Independent P Q := by
  decide

/-- `affects`, with a box read of an unresolved element (`rect:?`) changed by every box write.
$$\operatorname{affects}^{?}(o,i) \iff \operatorname{affects}(o,i) \lor \bigl((\exists m:\ o = \mathrm{rect}(m)) \land
i = \mathrm{rect}(\texttt{?})\bigr)$$
The conservative reading of an unresolved box read. -/
def affectsOpen (o i : Signal) : Bool :=
  affects o i || (match o, i with | .rect _, .rect "?" => true | _, _ => false)

/-- I3 under `affectsOpen`.
$$\mathrm{I3}^{?}(P,Q) \iff \bigl(\forall o \in \operatorname{effOut}(P),\ \forall i \in \mathrm{in}_Q:\
\lnot\operatorname{affects}^{?}(o,i)\bigr) \land \bigl(\forall o \in \operatorname{effOut}(Q),\ \forall i \in
\mathrm{in}_P:\ \lnot\operatorname{affects}^{?}(o,i)\bigr)$$
I1, I2 and I4 do not read signals. -/
def i3Open (P Q : PartSpec) : Bool :=
  !((effOut P).any fun o => Q.inputs.any (affectsOpen o)) && !((effOut Q).any fun o => P.inputs.any (affectsOpen o))

/-- The re-decided groups survive the conservative reading of `rect:?`: parts in different groups have no signal flow
even when every box write reaches every unresolved box read.

$$\forall P \in \mathrm{parts}_{\mathrm{code}},\ \forall Q \in \mathrm{parts}_{\mathrm{code}}:\ \lnot\operatorname{page}(P)
\to \lnot\operatorname{page}(Q) \to \kappa_{\mathrm{code}}(P) \ne \kappa_{\mathrm{code}}(Q) \to
\mathrm{I3}^{?}(P,Q)$$

So the `rect:?` limit hides no merge in these groups; hit tests and computed-style reads stay unmodelled. -/
theorem code_groups_rect_open :
    ∀ P ∈ codeParts, ∀ Q ∈ codeParts, ¬ pageLevel P → ¬ pageLevel Q → codeKey P ≠ codeKey Q → i3Open P Q = true := by
  decide

/-- The re-decided groups separate the declared rows too.

$$\forall P \in \mathrm{parts},\ \forall Q \in \mathrm{parts}:\ \lnot\operatorname{page}(\operatorname{wide}_{\mathrm{rows}}
(P)) \to \lnot\operatorname{page}(\operatorname{wide}_{\mathrm{rows}}(Q)) \to \kappa_{\mathrm{code}}(P) \ne
\kappa_{\mathrm{code}}(Q) \to \operatorname{Independent}(P,Q)$$

Follows from `code_groups_partition` and `independent_antitone`. -/
theorem code_groups_declared :
    ∀ P ∈ parts, ∀ Q ∈ parts, ¬ pageLevel (widen FootprintRows.rows P) → ¬ pageLevel (widen FootprintRows.rows Q) →
      codeKey P ≠ codeKey Q → Independent P Q := by
  intro P hP Q hQ hp hq hk
  have hk' : codeKey (widen FootprintRows.rows P) ≠ codeKey (widen FootprintRows.rows Q) := by
    unfold codeKey at hk ⊢
    rw [(widen_widens _ P).id, (widen_widens _ Q).id]
    exact hk
  exact independent_antitone (widen_widens _ P) (widen_widens _ Q)
    (code_groups_partition _ (List.mem_map_of_mem hP) _ (List.mem_map_of_mem hQ) hp hq hk')

/-- Every extracted access whose name or owner is `?` has a finding at its site, so an unresolved access never
enters the table unrecorded.

$$\forall a \in \mathrm{accesses}:\ \operatorname{open}(a) \to \operatorname{flagged}(\mathrm{findings}, a)$$

The extractor emits a finding (such as `dynamic-name` or `unresolved-target`) wherever it writes a `?`. -/
theorem flagged_total :
    ∀ a ∈ FootprintData.accesses, a.isOpen = true → Footprint.flagged FootprintData.findings a = true := by
  decide +kernel

/-- The page-level parts of the widened table: the scheduler and every part with a page scroll write outside mount,
resize, hover, event and cleanup callbacks.

$$[P.\mathrm{id} \mid P \in \mathrm{parts}_{\mathrm{code}},\ \operatorname{page}(P)] = [\texttt{engine.scroll},
\texttt{morph.mount}, \texttt{morph.tween}, \texttt{people.deck}]$$

morph.mount repins the page in its scroll-list callback (morph.mount/index.tsx:103-106), which its row omits; people.deck
is here because its env `scrollTo` (people.deck/index.tsx:55) is a callback the extractor cannot trace to its only
caller, the tab click (people.deck/driver.ts:204-216). -/
theorem code_pageLevel :
    (codeParts.filter pageLevel).map (·.id) = ["engine.scroll", "morph.mount", "morph.tween", "people.deck"] := by
  decide

/-- Text of `packages/contracts/golden/parts/footprint-diff.gen.json`: one diff line per row, the extractor's finding
count, the groups re-decided on the widened table and its page-level parts.

$$\operatorname{diffs} = \{\mathrm{parts}: [\operatorname{diff}(P) \mid P \in \mathrm{parts}],\ \mathrm{findings}:
|\mathrm{findings}|,\ \mathrm{codeGroups}: \mathrm{groups},\ \mathrm{codePageLevel}: [P.\mathrm{id} \mid P \in
\mathrm{parts}_{\mathrm{code}},\ \operatorname{page}(P)]\}$$

One row and one group per line, newline-terminated. -/
def diffText (_ : Unit := ()) : String :=
  "{\"parts\":[\n" ++ ",\n".intercalate (parts.map diffJson) ++ "\n],\n\"findings\":" ++
    toString FootprintData.findings.length ++ ",\n\"codeGroups\":[\n" ++
    ",\n".intercalate (FootprintRows.groups.map fun g => jarr (g.map jstr)) ++ "\n],\n\"codePageLevel\":" ++
    jarr ((codeParts.filter pageLevel).map (jstr ∘ (·.id))) ++ "}\n"

/-- One contract row as a JSON object on one line, with its group key and profiles.

$$\operatorname{row}(P) = \{\mathrm{id}, g, g_{\mathrm{plan}}, \kappa(P), o, \mathrm{in}, \mathrm{out}, \mathrm{ev}, T, M, A, \ell, s, \operatorname{page}(P), S(P)\}$$

`order` is `null` for a part outside the scroll list. -/
def rowJson (P : PartSpec) : String :=
  "{\"id\":" ++ jstr P.id ++ ",\"group\":" ++ jstr P.group.name ++ ",\"plan\":" ++ jstr P.plan.name ++
    ",\"groupKey\":" ++ jstr (groupKey P) ++
    ",\"order\":" ++ (match P.order with | some o => toString o | none => "null") ++
    ",\"inputs\":" ++ jarr (P.inputs.map (jstr ∘ Signal.wire)) ++
    ",\"outputs\":" ++ jarr (P.outputs.map (jstr ∘ Signal.wire)) ++
    ",\"onEvent\":" ++ jarr (P.onEvent.map (jstr ∘ Signal.wire)) ++
    ",\"targets\":" ++ jarr (P.targets.map jstr) ++ ",\"moves\":" ++ jarr (P.moves.map jstr) ++
    ",\"listAccess\":" ++ jarr (P.listAccess.map (jstr ∘ accessWire)) ++
    ",\"layoutLocal\":" ++ toString P.layoutLocal ++ ",\"schedules\":" ++ toString P.schedules ++
    ",\"pageLevel\":" ++ toString (pageLevel P) ++
    ",\"profiles\":" ++ jarr ((scenariosFor P).map jstr) ++ "}"

/-- Groups in wire order. $$[G_1, G_2, G_3, G_4, G_5, \mathrm{solo}]$$ Every constructor once. -/
def groups : List Group := [.g1, .g2, .g3, .g4, .g5, .solo]

/-- The premise every result over this table rests on, as written to the golden.
$$\mathrm{premise} = \texttt{declared-rows-unverified}$$
The rows are declared, not derived from code; consumers of the golden carry this field. -/
def premise : String := "declared-rows-unverified"

/-- Text of `packages/contracts/golden/parts/contracts.gen.json`: the rows, the members of each group, the code-wins
moves and the premise.

$$\operatorname{contracts} = \{\mathrm{parts}: [\operatorname{row}(P) \mid P \in \mathrm{parts}],\ \mathrm{groups}: g \mapsto \operatorname{members}(g),\ \mathrm{moved},\ \mathrm{premise}\}$$

One row per line, newline-terminated. -/
def contractsText (_ : Unit := ()) : String :=
  "{\"parts\":[\n" ++ ",\n".intercalate (parts.map rowJson) ++ "\n],\n\"groups\":{" ++
    ",".intercalate (groups.map fun g => jstr g.name ++ ":" ++ jarr ((members g).map jstr)) ++
    "},\n\"moved\":" ++ jarr (moved.map jstr) ++ ",\n\"premise\":" ++ jstr premise ++ "}\n"

/-- Text of `packages/measure-chromium/scenarios.gen.json`: for each used profile the parts measured under it, then
each part's profiles.

$$\operatorname{scenarios} = \{\mathrm{profiles}: p \mapsto [P.\mathrm{id} \mid P \in \mathrm{parts},\ p \in S(P)],\ \mathrm{parts}: [(P.\mathrm{id}, \kappa(P), S(P))]\}$$

Profiles no part uses are left out. -/
def scenariosText : String :=
  let used := profiles.filter fun p => parts.any fun P => (scenariosFor P).contains p
  "{\"profiles\":{\n" ++
    ",\n".intercalate (used.map fun p =>
      jstr p ++ ":" ++ jarr (((parts.filter fun P => (scenariosFor P).contains p)).map (jstr ∘ (·.id)))) ++
    "\n},\n\"parts\":[\n" ++
    ",\n".intercalate (parts.map fun P =>
      "{\"id\":" ++ jstr P.id ++ ",\"groupKey\":" ++ jstr (groupKey P) ++ ",\"profiles\":" ++
        jarr ((scenariosFor P).map jstr) ++ "}") ++ "\n]}\n"

/-- Byte comparison of one golden file. $$\operatorname{same}(f, t) \iff \operatorname{bytes}(f) = \operatorname{utf8}(t)$$
Prints which file differs. -/
def checkFile (path text : String) : IO Bool := do
  let cur ← IO.FS.readBinFile path
  if cur.data == text.toUTF8.data then
    IO.eprintln s!"contracts golden: {path} is up to date"
    return true
  IO.eprintln s!"contracts golden: {path} differs from the generated bytes"
  return false

/-- Text of `packages/contracts/golden/parts/footprint.gen.json` from the generated data.
$$\operatorname{footprint} = \operatorname{golden}(\mathrm{ids}, \mathrm{accesses}, \mathrm{findings})$$
Byte-equal to the extractor's output when the data module is fresh. -/
def footprintText (_ : Unit := ()) : String :=
  Footprint.golden FootprintData.partIds FootprintData.accesses FootprintData.findings

/-- Command-line driver (`lean/scripts/ContractsGolden.lean`): `--contracts`, `--scenarios`, `--diff` or `--rows`
prints that golden; `--check <contracts> <scenarios>` exits 0 when both files, `footprint.gen.json` and
`footprint-diff.gen.json` next to the contracts file and `Fw/Parts/FootprintRows.lean` under the working directory
hold exactly the generated bytes and every used profile has `profiles/<id>.json` next to the scenarios file, 1
otherwise.

$$\operatorname{run}(\texttt{--check}\ c\ s) = 0 \iff \operatorname{same}(c, \operatorname{contracts}) \land
\operatorname{same}(s, \operatorname{scenarios}) \land \operatorname{same}(\operatorname{dir}(c)/\texttt{footprint.gen.json},
\operatorname{footprint}) \land \operatorname{same}(\operatorname{dir}(c)/\texttt{footprint-diff.gen.json},
\operatorname{diffs}) \land \operatorname{same}(\texttt{Fw/Parts/FootprintRows.lean}, \operatorname{rowsFile}) \land
\forall P \in \mathrm{parts},\ \forall p \in S(P):\ \operatorname{exists}(\operatorname{dir}(s)/\texttt{profiles}/p\texttt{.json})$$

Any other argument list prints usage and returns 2; a missing golden file is an uncaught IO error. -/
def run (args : List String) : IO UInt32 := do
  match args with
  | ["--contracts"] => IO.print contractsText; return 0
  | ["--scenarios"] => IO.print scenariosText; return 0
  | ["--diff"] => IO.print diffText; return 0
  | ["--rows"] => IO.print rowsText; return 0
  | ["--check", c, s] =>
    let cdir := (System.FilePath.mk c).parent.getD "."
    let okR ← checkFile "Fw/Parts/FootprintRows.lean" rowsText
    let okF ← checkFile (cdir / "footprint.gen.json").toString footprintText
    let okD ← checkFile (cdir / "footprint-diff.gen.json").toString diffText
    let okC ← checkFile c contractsText
    let okS ← checkFile s scenariosText
    let dir := (System.FilePath.mk s).parent.getD "." / "profiles"
    let mut okP := true
    for p in profiles.filter fun p => parts.any fun P => (scenariosFor P).contains p do
      unless ← (dir / (p ++ ".json")).pathExists do
        IO.eprintln s!"contracts golden: profile {p} has no file in {dir}"
        okP := false
    return if okR && okF && okD && okC && okS && okP then 0 else 1
  | _ =>
    IO.eprintln "usage: ContractsGolden (--contracts | --scenarios | --diff | --rows | --check <contracts.gen.json> <scenarios.gen.json>)"
    return 2

#guard independent heroCountdown morphTween
#guard !independent heroExit heroOrbit
#guard !independent peopleCard pain
#guard !independent commission platform
#guard independent heroExit nav
#guard !independent engineScroll heroExit
#guard !independent morphTween heroExit
#guard affects .scrollY (.rect "pain") && !affects (.rect "pain") .scrollY && !affects .vh (.rect "pain")
#guard i3 heroAccent heroExit && !i3 heroAccent { hero with inputs := [.rect "hero"] }
#guard pageLevel morphTween && pageLevel engineScroll && !pageLevel nav
#guard parts.all fun P => !(effOut P).any fun o => o == .vw || o == .vh
#guard !i3 navHitTest navLangMenu
#guard !i2 heroAccent hero
#guard additive [readLayout, writeStyle] [] && !additive [writeStyle] [readLayout]
#guard groupKey people == "people" && groupKey nav == "g2"
#guard scenariosFor heroCountdown == ["fixture-rest"]
#guard scenariosFor heroExit == ["swipe-v1"]
#guard scenariosFor morphTween == ["swipe-wheel-v1", "swipe-touch-v1", "swipe-v1"]
#guard scenariosFor overlaysSignup == ["fixture-rest"]
#guard members .g4 == ["engine.scroll"]
#guard !independent peopleO peopleCard
#guard Signal.ofWire ("className", "data-fw-hidden/platform") == .scenePaused && Signal.ofWire ("vw", "") == .vw
#guard Signal.ofWire ("rect", "pain") == .rect "pain" && Signal.ofWire ("className", "x/nav") == .className "x/nav"
#guard FootprintRows.rows.all fun r =>
  (r.inputs ++ r.outputs ++ r.onEvent).all fun w => (Signal.ofWire w).fw == Footprint.joinKind w
#guard addNew [1, 2] [2, 3, 3] == [1, 2, 3] && addNew ([] : List Nat) [] == []
#guard components [heroExit, heroOrbit, morphTween] == [["hero.exit", "hero.orbit"]]
#guard components [heroExit, nav] == [["hero.exit"], ["nav"]]
#guard (widen [] people).inputs == people.inputs && (widen FootprintRows.rows peopleO).outputs.length ≥ 1
#guard codeKey people == "people" && codeKey painNotes == "commission" && codeKey morphTween == "morph.tween"
#guard independent peopleCarousel peopleO
#guard affectsOpen (.rect "hero") (.rect "?") && !affects (.rect "hero") (.rect "?") && !affectsOpen .vw (.rect "?")
#guard affectsOpen .scrollY (.rect "?") && !affectsOpen (.rect "hero") (.rect "pain")

end Fw.Parts.Contract
