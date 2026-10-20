import Lean.Data.Json
import Fw.Engine.Chromium
import Fw.Engine.WebKit
import Fw.Engine.Visual
import Fw.Parts.EndFlags
import Fw.Engine.Lessons
import Fw.Parts.Nav
import Fw.Parts.MorphPanel
/-!
# morph.panel: `blur(0)` → `none` at rest, and an own layer during the fade (MP)

**The original** (snapshot `_app/immutable/assets/2.gBuqKVzi.css`, rule `.start-selling-platform`): the platform
panel carries `filter: blur(calc((1 - var(--morph-fade)) * 12px))` and `opacity: var(--morph-fade)`, one rule in
every width band (the `@media` rules override only padding, gap, z-index and margins). The script
(`_app/immutable/nodes/2.DyWL8TcE.js`, `QM(e) = 1 - Math.min(1, e / KM)`, `KM = .55`) writes `--morph-fade` each
frame, so the fade is `φ = 1 - min(1, r / 0.55)`. At rest (`r ≤ 0`) the panel has `filter: blur(0px)`.

**What the engines do with `blur(0)`** (CONFIRMED unless marked):
* Chromium@f842f52 (`B = third_party/blink/renderer`): any non-empty filter list is `HasFilter`
  (`B/core/style/computed_style.h:540`), `blur(0)` appends one blur operation (`B/core/paint/filter_effect_builder.cc:465-470`),
  so `NeedsFilter` holds and `UpdateFilter` builds an effect node (`B/core/paint/paint_property_tree_builder.cc:2629-2651,
  2690-2740`). A non-composited filter effect is replayed as a `SaveLayer` with an image filter whenever its content
  is rastered (`B/platform/graphics/compositing/paint_chunks_to_cc_layer.cc:752-788`); with composited descendants it
  is a render surface (`RenderSurfaceReason::kFilter`, `B/platform/graphics/compositing/property_tree_manager.cc:1305-1308`).
* WebKit@862f17d (`WC = Source/WebCore`): `blur(0)` is an identity (`WC/style/values/filter-effects/StyleBlurFunction.h:56`,
  `WC/rendering/CSSFilterRenderer.cpp:263-281`), so `shouldPaintWithFilters` is false (`WC/rendering/RenderLayer.cpp:1062`):
  no painted filter. But `hasFilter` is `!filter.isNone()` (`WC/rendering/RenderElementStyleInlines.h:40`), it creates a
  group (`:96-106`), a group requires a `RenderLayer` (`WC/rendering/RenderBoxModelObject.cpp:930-933`), and a group with
  composited descendants is composited indirectly (`GraphicalEffect`, `WC/rendering/RenderLayerCompositor.cpp:4176-4182`).
* Both engines: a non-`none` filter makes a containing block for absolute and fixed descendants and a stacking
  context (R10, `research/notes/2026/10-18-engine-gaps.md:462-496`). On the lane band (`width ≤ 720px`) the underlay
  state sets `z-index: auto`, so the filter is the panel's only stacking-context reason at rest.

**What is proved.**
* Part math: `rest_iff` (radius 0 exactly when `r ≤ 0`), `filterO_rest`, `filterV_rest`, `filterV_fade`.
* (vis) E at rest, with the containing-block/stacking premise **RG10 as a hypothesis**: `rest_visSame_E`;
  `rest_groups_differ` shows the channel RG10 closes is real; `fade_scene_eq` needs no premise.
* (vis) Q during the fade with an own layer: `fade_visSame_Q` (the scenes are E; the class is Q because the blur moves
  from Skia raster to the compositor, which samples differently, so `PathPremises.raster_path` cannot be claimed).
* (work) at rest: `cr_rest_le`/`cr_rest_lt` and `wk_rest_le`/`wk_rest_lt` per frame, `cr_rest_claim` and
  `wk_rest_claim` per run (both `dominates`). WebKit gains only the compositor draw of the indirect layer and one
  resident layer (`wk_rest_layers`); `wk_rest_panel_not_mono` shows why a panel-level change at rest would break it.
* (work) at the rest↔fade toggle frames: in Chromium the `none`↔`blur` flip costs more, `cr_toggle_not_le`
  (stacking-context flip, full layout); in WebKit the toggle frames are equal, `wk_toggle_eqv` (the original's
  `blur(0)`↔`blur(x)` change also lays out). The rest win is not per-frame in Chromium.
* (work) WebKit over a whole swipe of rest, toggle and fade frames in any order: `wk_cross_le` (frame by frame),
  `wk_cross_resident`, `wk_cross_claim` (`dominates`). Model only: no CI run of the variant page measured the toggle
  frames yet, so the ledger claims the WebKit win on rest frames only.
* (work) during the fade. Chromium: **no claim**, `cr_fade_stages` (the blur write is `raster` on every layer
  state), `cr_fade_eq`, `cr_fade_noClaim`. WebKit: a **trade**, `wk_fade_le`, `wk_fade_paint_drop` (paint −1),
  `wk_fade_props_drop` (props −1), `fade_layers_up` (resident layers +1), `wk_fade_trade` (`claim = trade`).
* Changed since CI run 39088367495 (engine-model-fix): the Chromium fade was a trade (raster −1, by the refuted
  `ppFull` rule for a blur on an own layer) and the WebKit fade had no per-frame order (paint −2, props +2); the
  WebKit toggle frame was not dominated (one more layout unit).
* Golden rows for `rewrite+?fw=morph.panel:rest` against `rewrite`.

Premises are hypotheses. Exact arithmetic: `Rat` for progress, fade and radius; `Nat` for counts.
-/

namespace Fw.Parts.MorphPanelOpt

open Fw.Engine

/-! ## The part's math -/

/-- **The fade** the script writes into `--morph-fade` (`QM(e) = 1 - Math.min(1, e / .55)`; `20/11 = 1/0.55`).

The panel's fade value from the section progress `r`. -/
def fade (r : Rat) : Rat := 1 - min 1 (r * (20/11))

/-- **The blur radius in px** of `blur(calc((1 - φ) * 12px))`; `calc()` clamps a negative length to 0.

The blur radius for fade value `φ`. -/
def radius (φ : Rat) : Rat := max 0 ((1 - φ) * 12)

/-- One `blur(x)` filter operation.

The computed filter function `blur(x px)`. -/
def blurOp (x : Rat) : FilterOp := ⟨"blur", [x]⟩

/-- **The original's filter list**: always one blur, `blur(0)` included.

The original never drops the filter. -/
def filterO (φ : Rat) : List FilterOp := [blurOp (radius φ)]

/-- **The variant's filter list** (decision function): `none` when the radius is 0, else the original's blur.

The variant writes `filter: none` at rest and the same blur otherwise. -/
def filterV (φ : Rat) : List FilterOp := if radius φ = 0 then [] else filterO φ

#guard fade 0 == 1 && fade (11/20) == 0 && fade (11/40) == 1/2 && fade (-1) == 31/11 && fade 2 == 0
#guard radius 1 == 0 && radius (1/2) == 6 && radius 0 == 12 && radius 2 == 0
#guard filterV 1 == [] && filterO 1 == [⟨"blur", [0]⟩]
#guard filterV (1/2) == [⟨"blur", [6]⟩] && filterV (1/2) == filterO (1/2)
#guard filterV (fade (-3)) == [] && filterV (fade (1/100)) != []

/-- The radius is 0 exactly when the fade is at least 1.

No blur exactly at full fade. -/
theorem radius_eq_zero_iff (φ : Rat) : radius φ = 0 ↔ 1 ≤ φ := by
  unfold radius; grind

/-- The fade is at least 1 exactly when the progress is at most 0.

Full fade exactly at rest. -/
theorem fade_ge_one_iff (r : Rat) : 1 ≤ fade r ↔ r ≤ 0 := by
  unfold fade; grind

/-- **Rest is exactly `r ≤ 0`**: the blur radius is 0 exactly when the progress is at most 0.

The panel is unblurred exactly at rest. -/
theorem rest_iff (r : Rat) : radius (fade r) = 0 ↔ r ≤ 0 :=
  (radius_eq_zero_iff _).trans (fade_ge_one_iff r)

/-- At rest the original's filter is `blur(0)`.

The original keeps a zero blur at rest. -/
theorem filterO_rest {r : Rat} (h : r ≤ 0) : filterO (fade r) = [blurOp 0] := by
  simp only [filterO, (rest_iff r).mpr h]

/-- At rest the variant's filter is `none`.

The variant drops the filter at rest. -/
theorem filterV_rest {r : Rat} (h : r ≤ 0) : filterV (fade r) = [] := by
  simp only [filterV, (rest_iff r).mpr h, ↓reduceIte]

/-- During the fade both arms carry the same blur.

Outside rest the variant changes nothing in the filter. -/
theorem filterV_fade {r : Rat} (h : 0 < r) : filterV (fade r) = filterO (fade r) := by
  have : radius (fade r) ≠ 0 := fun h0 => absurd ((rest_iff r).mp h0) (by grind)
  simp only [filterV, this, ↓reduceIte]

/-! ## (vis): the scene -/

/-- An identity filter operation: `blur(0)`.

A filter function that leaves every pixel as it is. -/
def identityOp (op : FilterOp) : Bool := op.name == "blur" && op.args == [0]

/-- **The filter the rasterizer applies**: the list without identity operations. WebKit skips an identity list
(`RenderLayer.cpp:1062`, CONFIRMED); Chromium replays `blur(0)` as a `SaveLayer` whose blur of radius 0 returns its
input (INFERRED from Skia; a `SaveLayer` can drop LCD text, excluded by PLAN H1).

What the filter does to pixels. -/
def render (F : List FilterOp) : List FilterOp := F.filter fun op => !identityOp op

/-- **The containing-block and stacking-context channel** (R10): a non-`none` filter list, `blur(0)` included,
makes the panel a containing block for absolute and fixed descendants and a stacking context.

Whether the filter changes how descendants are placed and stacked. -/
def groups (F : List FilterOp) : Bool := !F.isEmpty

#guard render [blurOp 0] == [] && render [blurOp 3] == [blurOp 3] && render [] == []
#guard groups [blurOp 0] && !groups []

/-- **The original's scene**: a part-independent builder fed the applied filter and the group bit of `F_o`.

The page as the original draws it. -/
def sceneO {Env T : Type} (build : Env → T → List FilterOp → Bool → Scene) (r : Env → T → Rat) (env : Env)
    (t : T) : Scene :=
  build env t (render (filterO (fade (r env t)))) (groups (filterO (fade (r env t))))

/-- **The variant's scene**: the same builder fed the applied filter and the group bit of `F_v`.

The page as the variant draws it. -/
def sceneV {Env T : Type} (build : Env → T → List FilterOp → Bool → Scene) (r : Env → T → Rat) (env : Env)
    (t : T) : Scene :=
  build env t (render (filterV (fade (r env t)))) (groups (filterV (fade (r env t))))

/-- **Premise RG10** (R10): at every rest instant, the scene does not depend on whether the panel is a containing
block and a stacking context, i.e. no descendant is `position: fixed` or absolutely positioned against the panel,
and the z-indexed descendants stack the same (checked by PL0/PL2, not assumed).

Dropping the containing block and stacking context at rest changes nothing visible. -/
def RG10 {Env T : Type} (build : Env → T → List FilterOp → Bool → Scene) (r : Env → T → Rat) : Prop :=
  ∀ env t, r env t ≤ 0 → build env t [] true = build env t [] false

/-- **The channel RG10 closes is real**: at rest the original's filter groups and the variant's does not.

Without RG10 the variant could move or restack a descendant. -/
theorem rest_groups_differ {r : Rat} (h : r ≤ 0) :
    groups (filterO (fade r)) = true ∧ groups (filterV (fade r)) = false := by
  rw [filterO_rest h, filterV_rest h]; decide

/-- **During the fade the scenes are equal**, with no premise.

Outside rest the variant draws exactly what the original draws. -/
theorem fade_scene_eq {Env T : Type} (build : Env → T → List FilterOp → Bool → Scene) (r : Env → T → Rat)
    (env : Env) (t : T) (h : 0 < r env t) : sceneO build r env t = sceneV build r env t := by
  simp only [sceneO, sceneV, filterV_fade h]

/-- **(vis) at rest, class E**: under RG10, the visible scenes are equal in every environment (every width band)
and at every instant.

Replacing `blur(0)` with `none` is invisible whenever RG10 holds. -/
theorem rest_visSame_E {Env T : Type} (build : Env → T → List FilterOp → Bool → Scene) (r : Env → T → Rat)
    (vp : Env → Rect) (h : RG10 build r) : VisSame E vp (sceneO build r) (sceneV build r) := by
  intro env t
  show visible (vp env) (sceneO build r env t) = visible (vp env) (sceneV build r env t)
  by_cases hr : r env t ≤ 0
  · have ho : sceneO build r env t = build env t [] true := by
      simp only [sceneO, filterO_rest hr]; rfl
    have hv : sceneV build r env t = build env t [] false := by
      simp only [sceneV, filterV_rest hr]; rfl
    rw [ho, hv, h env t hr]
  · rw [fade_scene_eq build r env t (by grind)]

/-- **(vis) during the fade with an own layer, class Q.** The own layer is not part of the scene, so the scene is the
variant's scene and the relation holds under Q (via E). The claimed class is Q, not E: on its own layer the blur is
applied by the compositor instead of Skia raster, which samples differently, so pixel equality
(`PathPremises.raster_path`) is not claimed; the gate's `near` tolerances judge it (PL1/PL2).

Up to the gate's tolerances, the own-layer fade looks the same. -/
theorem fade_visSame_Q {Env T : Type} (build : Env → T → List FilterOp → Bool → Scene) (r : Env → T → Rat)
    (vp : Env → Rect) (h : RG10 build r) : VisSame Q vp (sceneO build r) (sceneV build r) :=
  visSame_E_Q (rest_visSame_E build r vp h)

/-! ## (work): the effect overlay -/

/-- **Extra work on given stages**: each listed stage runs (at least once) and gets one more unit.

One more operation on each stage in the list. -/
def bump (w : Work) (ss : List Stage) : Work where
  passes s := max (w.passes s) (if s ∈ ss then 1 else 0)
  units s := w.units s + (if s ∈ ss then 1 else 0)
  hits := w.hits

/-- Bumping never lowers work.

Extra work is extra. -/
theorem le_bump (w : Work) (ss : List Stage) : w.le (bump w ss) :=
  ⟨fun _ => ⟨Nat.le_max_left _ _, Nat.le_add_right _ _⟩, Nat.le_refl _⟩

/-- Bumping a stage is strictly more.

One more unit on a listed stage. -/
theorem lt_bump (w : Work) {ss : List Stage} {s : Stage} (hs : s ∈ ss) : w.lt (bump w ss) :=
  ⟨le_bump w ss, Or.inl ⟨s, Or.inr (by simp [bump, hs])⟩⟩

/-- **One rest frame**: the frame's own changes (no panel-level change at rest, as `--morph-fade` stays `1`), and
three facts about it: content painted in the panel's own chunks is rastered (`rasterUnder`), the panel's paint
properties are updated (`propsPanel`), the compositor draws while the panel has composited descendants
(`drawSurface`).

What happens in a rest frame besides the panel's filter. -/
structure RestIn (P : Type) where
  f : FrameIn P
  rasterUnder : Bool
  propsPanel : Bool
  drawSurface : Bool

/-- **The Chromium effect-node stages** of a rest frame: the `SaveLayer` replay on raster, the effect node's
property update, the render-surface draw (cites in the module doc).

The work Chromium's effect node adds to a frame. -/
def crEffectStages {P : Type} (x : RestIn P) : List Stage :=
  (if x.rasterUnder then [.raster] else []) ++ (if x.propsPanel then [.props] else []) ++
    (if x.drawSurface then [.comp] else [])

/-- **The WebKit effect stages** of a rest frame: `blur(0)` is an identity and is not painted, so only the compositor
draw of the indirectly composited panel layer remains (the layer exists, CONFIRMED; its per-frame draw, INFERRED).

The work WebKit's filter group adds to a frame. -/
def wkEffectStages {P : Type} (x : RestIn P) : List Stage := if x.drawSurface then [.comp] else []

open Fw.Engine.Chromium in
/-- **Chromium work of a rest frame** with filter list `F`: the frame's work, plus the effect stages when `F` is
non-empty (`HasFilter`).

What a rest frame costs in Chromium. -/
def crRestW (F : List FilterOp) (x : RestIn CrProp) : Work :=
  if groups F then bump (frameWork chromium x.f) (crEffectStages x) else frameWork chromium x.f

open Fw.Engine.WebKit in
/-- **WebKit work of a rest frame** with filter list `F`: the frame's work, plus the effect stages when `F` is not
`none` (`hasFilter`).

What a rest frame costs in WebKit. -/
def wkRestW (F : List FilterOp) (x : RestIn WkProp) : Work :=
  if groups F then bump (frameWork webkit x.f) (wkEffectStages x) else frameWork webkit x.f

/-! ## (work) at rest: dominance -/

/-- **(work) at rest, Chromium, per frame**: the variant is at most the original.

Dropping `blur(0)` never adds Chromium work in a rest frame. -/
theorem cr_rest_le {r : Rat} (hr : r ≤ 0) (x : RestIn Chromium.CrProp) :
    (crRestW (filterV (fade r)) x).le (crRestW (filterO (fade r)) x) := by
  rw [filterV_rest hr, filterO_rest hr]; exact le_bump _ _

/-- **(work) at rest, Chromium, strict**: one fewer `SaveLayer` replay, effect-node update or render-surface draw
whenever the frame has one.

The removed effect node saves work in every frame that touches it. -/
theorem cr_rest_lt {r : Rat} (hr : r ≤ 0) (x : RestIn Chromium.CrProp)
    (hx : x.rasterUnder = true ∨ x.propsPanel = true ∨ x.drawSurface = true) :
    (crRestW (filterV (fade r)) x).lt (crRestW (filterO (fade r)) x) := by
  rw [filterV_rest hr, filterO_rest hr]
  rcases hx with h | h | h
  · exact lt_bump _ (s := .raster) (by simp [crEffectStages, h])
  · exact lt_bump _ (s := .props) (by simp [crEffectStages, h])
  · exact lt_bump _ (s := .comp) (by simp [crEffectStages, h])

/-- **(work) at rest, WebKit, per frame**: the variant is at most the original.

Dropping `blur(0)` never adds WebKit work in a rest frame. -/
theorem wk_rest_le {r : Rat} (hr : r ≤ 0) (x : RestIn WebKit.WkProp) :
    (wkRestW (filterV (fade r)) x).le (wkRestW (filterO (fade r)) x) := by
  rw [filterV_rest hr, filterO_rest hr]; exact le_bump _ _

/-- **(work) at rest, WebKit, strict**: one fewer compositor draw of the indirect panel layer in every frame the
compositor draws it. Painting saves nothing (`blur(0)` is an identity).

WebKit's only per-frame saving is the compositor draw. -/
theorem wk_rest_lt {r : Rat} (hr : r ≤ 0) (x : RestIn WebKit.WkProp) (hx : x.drawSurface = true) :
    (wkRestW (filterV (fade r)) x).lt (wkRestW (filterO (fade r)) x) := by
  rw [filterV_rest hr, filterO_rest hr]
  exact lt_bump _ (s := .comp) (by simp [wkEffectStages, hx])

/-- Pointwise `≤` lifts to aligned runs.

Frame-by-frame order gives run order. -/
theorem leAll_map {α : Type} (g h : α → Work) (hle : ∀ x, (g x).le (h x)) :
    ∀ xs : List α, leAll (xs.map g) (xs.map h) = true
  | [] => rfl
  | x :: xs => by
    simp only [List.map_cons, leAll, Bool.and_eq_true]
    exact ⟨(Work.leb_iff _ _).mpr (hle x), leAll_map g h hle xs⟩

/-- One strictly smaller frame makes `someLt` true.

A strict frame shows in the run. -/
theorem someLt_map {α : Type} (g h : α → Work) :
    ∀ xs : List α, (∃ x ∈ xs, (g x).lt (h x)) → someLt (xs.map g) (xs.map h) = true
  | [], ⟨_, hx, _⟩ => absurd hx List.not_mem_nil
  | x :: xs, ⟨y, hy, hlt⟩ => by
    simp only [someLt, List.map_cons, List.zip_cons_cons, List.any_cons, Bool.or_eq_true]
    rcases List.mem_cons.mp hy with rfl | hy
    · exact Or.inl ((Work.ltb_iff _ _).mpr hlt)
    · exact Or.inr (someLt_map g h xs ⟨y, hy, hlt⟩)

/-- **(work) at rest, Chromium, per run: dominates.** Over any run of rest frames with one frame that touches the
effect node, the claim is "dominates"; the render surface is not a composited layer, so the resident state is the
same in both arms.

At rest the Chromium variant dominates. -/
theorem cr_rest_claim {r : Rat} (hr : r ≤ 0) (xs : List (RestIn Chromium.CrProp))
    (hx : ∃ x ∈ xs, x.rasterUnder = true ∨ x.propsPanel = true ∨ x.drawSurface = true) (res : Resident) :
    claim (Screen.screen (toRun (xs.map (crRestW (filterO (fade r))))) (toRun (xs.map (crRestW (filterV (fade r))))))
      res res = .dominates := by
  obtain ⟨x, hm, h⟩ := hx
  rw [run_claim res res (leAll_map _ _ (cr_rest_le hr) xs) (someLt_map _ _ xs ⟨x, hm, cr_rest_lt hr x h⟩)]
  simp [Resident.le]

/-- **WebKit resident state** with filter list `F`: one more composited layer (and its backing, `kpx`) when the
filter groups and the panel has composited descendants (`GraphicalEffect`).

What the panel's filter keeps resident in WebKit. -/
def wkResident (F : List FilterOp) (desc : Bool) (res : Resident) (kpx : Nat) : Resident :=
  if groups F && desc then ⟨res.layers + 1, res.backingKpx + kpx⟩ else res

/-- **WebKit at rest: one fewer composited layer** when the panel has composited descendants.

Dropping `blur(0)` frees the indirect layer. -/
theorem wk_rest_layers {r : Rat} (hr : r ≤ 0) (desc : Bool) (res : Resident) (kpx : Nat) :
    (wkResident (filterV (fade r)) desc res kpx).layers + (if desc then 1 else 0) =
      (wkResident (filterO (fade r)) desc res kpx).layers := by
  rw [filterV_rest hr, filterO_rest hr]; cases desc <;> rfl

/-- **(work) at rest, WebKit, per run: dominates**, with the resident state not growing (it shrinks with composited
descendants).

At rest the WebKit variant dominates once the compositor draws the panel. -/
theorem wk_rest_claim {r : Rat} (hr : r ≤ 0) (xs : List (RestIn WebKit.WkProp)) (hx : ∃ x ∈ xs, x.drawSurface = true)
    (desc : Bool) (res : Resident) (kpx : Nat) :
    claim (Screen.screen (toRun (xs.map (wkRestW (filterO (fade r))))) (toRun (xs.map (wkRestW (filterV (fade r))))))
      (wkResident (filterV (fade r)) desc res kpx) (wkResident (filterO (fade r)) desc res kpx) = .dominates := by
  obtain ⟨x, hm, h⟩ := hx
  rw [run_claim _ _ (leAll_map _ _ (wk_rest_le hr) xs) (someLt_map _ _ xs ⟨x, hm, wk_rest_lt hr x h⟩)]
  rw [filterV_rest hr, filterO_rest hr]
  cases desc <;> simp [wkResident, groups, Resident.le]

/-- The panel element (part-local id).

The `.start-selling-platform` box. -/
def panel : Nat := 0

open Fw.Engine.WebKit in
/-- **Why the rest win needs no panel-level change at rest** (`wk_not_mono`): an opacity change on the panel is a
recomposite on the original's indirectly composited layer but a layer repaint on the variant's non-composited layer,
so the variant's frame is not below the original's.

Losing the composited layer makes later panel changes repaint. -/
theorem wk_rest_panel_not_mono :
    ¬ (frameWork webkit (jsFrame [⟨panel, .opacity, .layer⟩])).le
      (frameWork webkit (jsFrame [⟨panel, .opacity, .own⟩])) := by
  decide

/-! ## The rest↔fade toggle frames: not dominated in Chromium, equal in WebKit -/

open Fw.Engine.Chromium in
/-- **Chromium toggle frame**: the variant's `none`↔`blur` flip turns the panel's stacking context on or off, which
forces a full layout (`B/core/style/computed_style.cc:779-784`, CONFIRMED). So when the original's frame runs no
layout, the variant's toggle frame is not below it, whatever effect stages `S` (without `layout`) the original adds.

The flip frame costs a layout the original never pays. -/
theorem cr_toggle_not_le (f : FrameIn CrProp) (ss : List Stage) (hs : Stage.layout ∉ ss)
    (h0 : (frameWork chromium f).passes .layout = 0) :
    ¬ (bump (frameWork chromium f) CrLevel.layoutFull.stages).le (bump (frameWork chromium f) ss) := by
  intro h
  have := (h.1 .layout).1
  simp [bump, hs, h0, CrLevel.stages] at this

/-- The custom property the script writes (part-local id).

`--morph-fade`. -/
def fadeVar : Nat := 0

open Fw.Engine.Chromium in
/-- **The `--morph-fade` write** in Chromium: a custom property read by `filter` (a blur) and `opacity`.

One fade step as Chromium sees it. -/
def fadeProp : CrProp := .custom fadeVar [.filter true, .opacity]

open Fw.Engine.Chromium in
/-- **A fade frame in Chromium**: one script callback that writes `--morph-fade` on the panel in layer state `ℓ`,
plus other changes `C`.

The frame the fade writes. -/
def crFade (ℓ : LayerState) (cs : List (Change CrProp)) : FrameIn CrProp :=
  jsWrite 1 (⟨panel, fadeProp, ℓ⟩ :: cs)

open Fw.Engine.Chromium in
/-- The Chromium enter frame without other changes runs no layout, so `cr_toggle_not_le` applies to it.

A plain fade write does not lay out. -/
theorem cr_enter_layout_zero : (frameWork chromium (crFade .layer [])).passes .layout = 0 := by decide

open Fw.Engine.WebKit in
/-- **The original's WebKit toggle frame** (enter or leave): opacity crosses 1, and the filter value changes.

`blur(0)` ↔ `blur(x)` with the opacity flip. -/
def wkEdgeO (ℓ : LayerState) : FrameIn WkProp := jsFrame [⟨panel, .opacityCross1, ℓ⟩, ⟨panel, .filter, ℓ⟩]

open Fw.Engine.WebKit in
/-- **The variant's WebKit toggle frame**: opacity crosses 1, and the filter appears or disappears.

`none` ↔ `blur(x)` with the opacity flip. -/
def wkEdgeV (ℓ : LayerState) : FrameIn WkProp := jsFrame [⟨panel, .opacityCross1, ℓ⟩, ⟨panel, .filterToggle, ℓ⟩]

open Fw.Engine.WebKit in
/-- **WebKit toggle frame, layout units**: the flip is a layout change (`filterToggle` has raw level Layout,
`WC/style/StyleDifference.cpp:217`), and so is the original's `blur(0)` ↔ `blur(x)` value change, because it changes
the filter outsets (`WC/style/StyleDifference.cpp:68-83`@862f17d, CONFIRMED; MEASURED by the engine-premises lane).
Both arms lay out 2 changes.

Changed since CI run 39088367495: the original's filter change was modelled as no layout (1 unit against 2).

Both toggle frames lay out the panel twice. -/
theorem wk_toggle_layout_units (ℓ : LayerState) :
    (frameWork webkit (wkEdgeV ℓ)).units .layout = 2 ∧ (frameWork webkit (wkEdgeO ℓ)).units .layout = 2 := by
  cases ℓ <;> decide

open Fw.Engine.WebKit in
/-- **WebKit toggle frame, passes equal**: the opacity flip already lays out in both arms.

Same stages run in both arms. -/
theorem wk_toggle_passes (ℓ : LayerState) (s : Stage) :
    (frameWork webkit (wkEdgeV ℓ)).passes s = (frameWork webkit (wkEdgeO ℓ)).passes s := by
  cases ℓ <;> cases s <;> decide

open Fw.Engine.WebKit in
/-- **WebKit toggle frame: equal work.** The variant's toggle frame and the original's have the same work in both
directions of `≼`: each change in either arm is a Layout-level difference.

Changed since CI run 39088367495: this replaces `wk_toggle_not_le` (the variant's frame was not below the
original's, by one layout unit), which the corrected filter rule refutes.

On WebKit the `none` ↔ `blur` flip costs nothing over the original's toggle. -/
theorem wk_toggle_eqv (ℓ : LayerState) :
    (frameWork webkit (wkEdgeV ℓ)).eqv (frameWork webkit (wkEdgeO ℓ)) := by
  cases ℓ <;> exact ⟨frame_le_union webkit (by decide), frame_le_union webkit (by decide)⟩

/-! ## WebKit over a whole run that crosses rest and fade (`wk_cross_claim`) -/

/-- **One frame of a WebKit run** of the rest variant: a rest frame (`φ = 1`), a toggle frame (opacity crosses 1 and
the filter flips, layer state `ℓ`), or a fade frame with work `w`. A fade frame is the same in both arms, because the
variant writes the original's filter whenever `φ < 1` (`filterV_fade`).

The three kinds of frame in a swipe that leaves rest and comes back. -/
inductive WkCross where
  | rest (x : RestIn WebKit.WkProp)
  | edge (ℓ : LayerState)
  | fade (w : Work)

open Fw.Engine.WebKit in
/-- **The original's WebKit work** of one frame: `blur(0)` at rest, the `blur(0)` ↔ `blur(x)` toggle, the fade
frame's work.

What each frame of the run costs the original. -/
def wkCrossO : WkCross → Work
  | .rest x => wkRestW (filterO 1) x
  | .edge ℓ => frameWork webkit (wkEdgeO ℓ)
  | .fade w => w

open Fw.Engine.WebKit in
/-- **The variant's WebKit work** of one frame: `none` at rest, the `none` ↔ `blur(x)` toggle, the fade frame's work.

What each frame of the run costs the variant. -/
def wkCrossV : WkCross → Work
  | .rest x => wkRestW (filterV 1) x
  | .edge ℓ => frameWork webkit (wkEdgeV ℓ)
  | .fade w => w

/-- `φ = 1` is rest: the progress `0` gives the full fade.

Rest frames use the filters at `φ = 1`. -/
theorem fade_zero : fade 0 = 1 := by unfold fade; grind

/-- **WebKit, every frame of the run**: the variant is at most the original, frame by frame (rest by `wk_rest_le`,
toggle by `wk_toggle_eqv`, fade equal).

No frame of a rest-fade-rest swipe costs WebKit more. -/
theorem wk_cross_le (c : WkCross) : (wkCrossV c).le (wkCrossO c) := by
  cases c with
  | rest x => have h := wk_rest_le (r := 0) (by decide) x; rw [fade_zero] at h; exact h
  | edge ℓ => exact (wk_toggle_eqv ℓ).1
  | fade w => exact Work.le_refl w

/-- **WebKit resident state over the run**: whatever fade value `φ` the variant's resident state is taken at, and
`φ'` the original's, the variant's is at most the original's (the original's filter is never `none`).

The variant never keeps more layers or backing than the original. -/
theorem wk_cross_resident (φ φ' : Rat) (desc : Bool) (res : Resident) (kpx : Nat) :
    (wkResident (filterV φ) desc res kpx).le (wkResident (filterO φ') desc res kpx) := by
  unfold filterV
  split
  · cases desc <;> simp [wkResident, groups, filterO, Resident.le]
  · cases desc <;> simp [wkResident, groups, filterO, Resident.le]

/-- **(work) WebKit, a whole run across rest and fade: dominates.** For any run of rest, toggle and fade frames in
any order with one rest frame in which the compositor draws the panel, the claim is "dominates", with the variant's
resident state taken at any fade value `φ` and the original's at any `φ'` (so also at the run's peak).

In the model, the WebKit rest variant wins over the whole swipe, toggle frames included. -/
theorem wk_cross_claim (xs : List WkCross) (hx : ∃ x, WkCross.rest x ∈ xs ∧ x.drawSurface = true)
    (φ φ' : Rat) (desc : Bool) (res : Resident) (kpx : Nat) :
    claim (Screen.screen (toRun (xs.map wkCrossO)) (toRun (xs.map wkCrossV)))
      (wkResident (filterV φ) desc res kpx) (wkResident (filterO φ') desc res kpx) = .dominates := by
  obtain ⟨x, hm, h⟩ := hx
  have hlt : (wkCrossV (.rest x)).lt (wkCrossO (.rest x)) := by
    have h' := wk_rest_lt (r := 0) (by decide) x h; rw [fade_zero] at h'; exact h'
  rw [run_claim _ _ (leAll_map _ _ wk_cross_le xs) (someLt_map _ _ xs ⟨_, hm, hlt⟩)]
  simp [wk_cross_resident]

#guard claim (Screen.screen (toRun ([WkCross.rest ⟨WebKit.jsFrame [], false, false, true⟩, .edge .layer,
    .fade Work.zero, .edge .layer, .rest ⟨WebKit.jsFrame [], false, false, true⟩].map wkCrossO))
  (toRun ([WkCross.rest ⟨WebKit.jsFrame [], false, false, true⟩, .edge .layer, .fade Work.zero, .edge .layer,
    .rest ⟨WebKit.jsFrame [], false, false, true⟩].map wkCrossV))) ⟨0, 0⟩ ⟨1, 0⟩ == .dominates

/-! ## (work) during the fade: an own layer is a trade -/

/-- A pairwise cover of a list with itself.

Every change covers itself. -/
theorem coverB_self {P M : Type} (E : Engine P M) : ∀ cs : List (Change P), coverB E cs cs = true
  | [] => rfl
  | c :: cs => by simp [coverB, coverB_self E cs]

open Fw.Engine.Chromium in
/-- **Chromium fade frame, per frame `≤`**: the fade write re-rasters (`raster`) on every layer state, so the own
layer adds no work in a fade frame (the frames are in fact equal, `cr_fade_eq`).

Changed since CI run 39088367495: on its own layer the blur write was modelled as a property-tree update (`ppFull`,
below `raster`); the engine-premises lane MEASURED a raster for a blur value change on an own layer.

The own layer never adds work in a fade frame. -/
theorem cr_fade_le (ℓo : LayerState) (h : ℓo ≠ .own) (cs : List (Change CrProp)) :
    (frameWork chromium (crFade .own cs)).le (frameWork chromium (crFade ℓo cs)) := by
  refine frame_le_of_cover chromium (crFade ℓo cs).changes [] (by simp) ?_ (Nat.le_refl _) (Nat.le_refl _)
    (Nat.le_refl _) (Nat.le_refl _) (Nat.le_refl _)
  simp only [crFade, jsWrite, coverB, coverB_self, Bool.and_true]
  cases ℓo
  · decide
  · decide
  · exact absurd rfl h

open Fw.Engine.Chromium in
/-- **The fade write re-rasters on every layer state**: the `--morph-fade` write's stages are the `raster` level's,
whether the panel is unlayered, on a shared layer or on its own layer (a blur value change on an own layer is
`raster`, `keyLevel`).

Changed since CI run 39088367495: this replaces `cr_fade_raster_drop` (one raster unit fewer per fade frame on the
own layer), which the engine-premises lane refuted (MEASURED: raster on `filter(blur)` at `own`).

The own layer does not take the blur off the raster path. -/
theorem cr_fade_stages (ℓ : LayerState) :
    chromium.stagesOf ⟨panel, fadeProp, ℓ⟩ = CrLevel.raster.stages := by
  cases ℓ <;> decide

open Fw.Engine.Chromium in
/-- **Chromium fade frames are equal** in both arms: the fade frame on the own layer has the same work as on any
other layer state.

An own layer changes no counted work in a Chromium fade frame. -/
theorem cr_fade_eq (ℓo : LayerState) (cs : List (Change CrProp)) :
    frameWork chromium (crFade .own cs) = frameWork chromium (crFade ℓo cs) := by
  cases ℓo <;> rfl

/-- **Resident state with or without the panel's own layer**: one more composited layer and its backing `kpx`.

The cost of the own layer while it exists. -/
def ownResident (own : Bool) (res : Resident) (kpx : Nat) : Resident :=
  if own then ⟨res.layers + 1, res.backingKpx + kpx⟩ else res

/-- **The layer increase**: the own layer adds exactly one resident layer.

Layers +1 during the fade. -/
theorem fade_layers_up (res : Resident) (kpx : Nat) :
    (ownResident true res kpx).layers = (ownResident false res kpx).layers + 1 := rfl

open Fw.Engine.Chromium in
/-- **(work) during the fade, Chromium: no claim.** Over any run of fade frames the two arms have equal counted work
(`cr_fade_eq`), so the claim is "noClaim" whatever the resident states (`resident_only_noClaim`); the own layer only
adds a resident layer (`fade_layers_up`).

Changed since CI run 39088367495: this replaces `cr_fade_trade` (claim "trade": raster down, layers up), which rested
on the refuted `ppFull` rule for a blur on an own layer. The sign of the Chromium half changed from trade to no-win.

Same raster, one more layer. -/
theorem cr_fade_noClaim (ℓo : LayerState) (css : List (List (Change CrProp))) (res : Resident) (kpx : Nat) :
    claim (Screen.screen (toRun (css.map fun cs => frameWork chromium (crFade ℓo cs)))
        (toRun (css.map fun cs => frameWork chromium (crFade .own cs))))
      (ownResident true res kpx) (ownResident false res kpx) = .noClaim := by
  apply resident_only_noClaim
  rw [show (fun cs => frameWork chromium (crFade .own cs)) = (fun cs => frameWork chromium (crFade ℓo cs)) from
    funext fun cs => cr_fade_eq ℓo cs]

open Fw.Engine.WebKit in
/-- **The original's WebKit fade frame** on a non-composited panel: the blur value change and the opacity change.
The blur radius changes every fade frame, so the filter outsets change: the change is `filter`, not
`filterPainted` (same outsets).

Changed since CI run 39088367495: the first change was `filterPainted`, which since that run means a same-outset
filter change; the fade's radius change is the outset-changing `filter`.

One fade step, painted. -/
def wkFadeO (cs : List (Change WkProp)) : FrameIn WkProp :=
  jsFrame (⟨panel, .filter, .layer⟩ :: ⟨panel, .opacity, .layer⟩ :: cs)

open Fw.Engine.WebKit in
/-- **The variant's WebKit fade frame** on the own layer: the composited filter and the opacity change.

One fade step, composited. -/
def wkFadeV (cs : List (Change WkProp)) : FrameIn WkProp :=
  jsFrame (⟨panel, .filter, .own⟩ :: ⟨panel, .opacity, .own⟩ :: cs)

open Fw.Engine.WebKit in
/-- **WebKit fade: the paint drop.** The opacity change leaves `paint` on the own layer; the blur change paints in
both arms (it is a Layout-level change).

Changed since CI run 39088367495: the drop was 2 units (the filter change also left paint); the corrected filter
rule makes the blur change Layout on every layer state.

One paint unit fewer per fade frame. -/
theorem wk_fade_paint_drop (cs : List (Change WkProp)) :
    (frameWork webkit (wkFadeV cs)).units .paint + 1 = (frameWork webkit (wkFadeO cs)).units .paint := by
  have h1 : decide (Stage.paint ∈ webkit.stagesOf ⟨panel, .filter, .own⟩) = true := by decide
  have h2 : decide (Stage.paint ∈ webkit.stagesOf ⟨panel, .opacity, .own⟩) = false := by decide
  have h3 : decide (Stage.paint ∈ webkit.stagesOf ⟨panel, .filter, .layer⟩) = true := by decide
  have h4 : decide (Stage.paint ∈ webkit.stagesOf ⟨panel, .opacity, .layer⟩) = true := by decide
  simp only [frameWork, stageUnits, wkFadeV, wkFadeO, jsFrame, List.countP_cons, h1, h2, h3, h4]
  simp

open Fw.Engine.WebKit in
/-- **WebKit fade: the props drop.** By the compositing table (`wkCompUpdate`) an opacity change on an own layer
runs no compositing update, while on a shared layer it does; the blur change runs one in both arms.

Changed since CI run 39088367495: this replaces `wk_fade_props_up` (props +2 per fade frame), which the
engine-premises lane refuted (MEASURED: opacity at `own` runs no compositing update, at `layer` it runs one).

One props unit fewer per fade frame. -/
theorem wk_fade_props_drop (cs : List (Change WkProp)) :
    (frameWork webkit (wkFadeV cs)).units .props + 1 = (frameWork webkit (wkFadeO cs)).units .props := by
  have h1 : decide (Stage.props ∈ webkit.stagesOf ⟨panel, .filter, .own⟩) = true := by decide
  have h2 : decide (Stage.props ∈ webkit.stagesOf ⟨panel, .opacity, .own⟩) = false := by decide
  have h3 : decide (Stage.props ∈ webkit.stagesOf ⟨panel, .filter, .layer⟩) = true := by decide
  have h4 : decide (Stage.props ∈ webkit.stagesOf ⟨panel, .opacity, .layer⟩) = true := by decide
  simp only [frameWork, stageUnits, wkFadeV, wkFadeO, jsFrame, List.countP_cons, h1, h2, h3, h4]
  simp

open Fw.Engine.WebKit in
/-- **WebKit fade frame, per frame `≤`**: each of the variant's panel changes is covered by the original's change of
the same property, so the own layer adds no work in a fade frame.

Changed since CI run 39088367495: this replaces `wk_fade_not_le` (no per-frame order, paint down and props up).

On WebKit the own layer never adds work in a fade frame. -/
theorem wk_fade_le (cs : List (Change WkProp)) :
    (frameWork webkit (wkFadeV cs)).le (frameWork webkit (wkFadeO cs)) := by
  refine frame_le_of_cover webkit (wkFadeO cs).changes [] (by simp) ?_ (Nat.le_refl _) (Nat.le_refl _)
    (Nat.le_refl _) (Nat.le_refl _) (Nat.le_refl _)
  simp only [wkFadeV, wkFadeO, jsFrame, coverB, coverB_self, Bool.and_true]
  decide

open Fw.Engine.WebKit in
/-- **(work) during the fade, WebKit: a trade.** Over any non-empty run of fade frames, the variant is below the
original frame by frame (`wk_fade_le`, strict by `wk_fade_paint_drop`) but holds one more layer
(`fade_layers_up`), so the claim is "trade", never "dominates".

New since CI run 39088367495 (the WebKit half was "no per-frame order" before).

Paint and props down, layers up. -/
theorem wk_fade_trade (css : List (List (Change WkProp))) (hne : css ≠ []) (res : Resident) (kpx : Nat) :
    claim (Screen.screen (toRun (css.map fun cs => frameWork webkit (wkFadeO cs)))
        (toRun (css.map fun cs => frameWork webkit (wkFadeV cs))))
      (ownResident true res kpx) (ownResident false res kpx) = .trade := by
  have hlt : ∀ cs, (frameWork webkit (wkFadeV cs)).lt (frameWork webkit (wkFadeO cs)) := fun cs =>
    ⟨wk_fade_le cs, Or.inl ⟨.paint, Or.inr (by have := wk_fade_paint_drop cs; omega)⟩⟩
  obtain ⟨c, cs', rfl⟩ : ∃ c cs', css = c :: cs' := by
    cases css with
    | nil => exact absurd rfl hne
    | cons c cs' => exact ⟨c, cs', rfl⟩
  rw [run_claim _ _ (leAll_map _ _ (fun cs => wk_fade_le cs) _)
    (someLt_map _ _ _ ⟨c, List.mem_cons_self, hlt c⟩)]
  simp [ownResident, Resident.le]
  intro h; omega

/-! ## Golden rows for `engine-check`

The golden variant is `rewrite+?fw=morph.panel:rest` against base `rewrite`: only sub-claim 1 (`blur(0)` → `none`
at rest). Sub-claim 2 (own layer during the fade) is a trade (WebKit) or no claim (Chromium) and gets no golden
row. The swipe is modelled as eight frames `[rest, rest, enter, fade, fade, leave, rest, rest]`; the lane is one width band (430 px), so one schedule
covers all bands the profiles run. -/

/-- The rest frame of the swipe: one script callback with no style change on the panel, and the compositor draws
the panel's effect surface (`drawSurface`).

A scroll frame while the panel rests. -/
def restCr : RestIn Chromium.CrProp := ⟨Chromium.jsWrite 1 [], false, false, true⟩

/-- The WebKit rest frame, as `restCr`.

A scroll frame while the panel rests. -/
def restWk : RestIn WebKit.WkProp := ⟨WebKit.jsFrame [], false, false, true⟩

open Fw.Engine.Chromium in
/-- The Chromium fade frame, identical in both arms of the golden variant: the `--morph-fade` write on the
non-composited panel plus the compositor draw of its effect.

One fade step in Chromium. -/
def fadeCr : Work := bump (frameWork chromium (crFade .layer [])) [.comp]

/-- **The Chromium original arm**: rest frames carry the `blur(0)` effect; enter, fade and leave are fade frames.

What the original's swipe costs in Chromium. -/
def crO : List Work :=
  let r := crRestW (filterO (fade 0)) restCr
  [r, r, fadeCr, fadeCr, fadeCr, fadeCr, r, r]

/-- **The Chromium variant arm**: rest frames have no effect; the enter and leave frames add the stacking-context
flip (full layout).

What the variant's swipe costs in Chromium. -/
def crV : List Work :=
  let r := crRestW (filterV (fade 0)) restCr
  let e := bump fadeCr Chromium.CrLevel.layoutFull.stages
  [r, r, e, fadeCr, fadeCr, e, r, r]

open Fw.Engine.WebKit in
/-- The WebKit fade frame, identical in both arms: filter and opacity changes on the indirectly composited panel
plus the compositor draw.

One fade step in WebKit. -/
def fadeWk : Work := bump (frameWork webkit (jsFrame [⟨panel, .filter, .own⟩, ⟨panel, .opacity, .own⟩])) [.comp]

open Fw.Engine.WebKit in
/-- **The WebKit original arm**: the toggle frames change the filter value (`filter`).

What the original's swipe costs in WebKit. -/
def wkO : List Work :=
  let r := wkRestW (filterO (fade 0)) restWk
  let e := bump (frameWork webkit (wkEdgeO .own)) [.comp]
  [r, r, e, fadeWk, fadeWk, e, r, r]

open Fw.Engine.WebKit in
/-- **The WebKit variant arm**: the toggle frames add or remove the filter (`filterToggle`).

What the variant's swipe costs in WebKit. -/
def wkV : List Work :=
  let r := wkRestW (filterV (fade 0)) restWk
  let e := bump (frameWork webkit (wkEdgeV .own)) [.comp]
  [r, r, e, fadeWk, fadeWk, e, r, r]

/-- One count type: its name, the stage it counts, whether it counts units (else passes), and whether its class is
frame-exact (else judged by totals).

How a measured counter maps to the model. -/
structure CountType where
  name : String
  stage : Stage
  units : Bool
  exact : Bool

/-- The JSON name of a stage.

As in the engine golden files. -/
def stageName : Stage → String
  | .script => "script" | .style => "style" | .layout => "layout" | .props => "props"
  | .paint => "paint" | .raster => "raster" | .commit => "commit" | .comp => "comp"

#guard stageName .layout == "layout" && stageName .comp == "comp"

/-- The per-frame series of one count type over an arm.

What the counter would read frame by frame. -/
def series (ws : List Work) (t : CountType) : List Nat :=
  ws.map fun w => if t.units then w.units t.stage else w.passes t.stage

#guard series crV ⟨"x", .layout, false, false⟩ == [0, 0, 1, 0, 0, 1, 0, 0]
#guard series crO ⟨"x", .layout, false, false⟩ == [0, 0, 0, 0, 0, 0, 0, 0]

/-- **The prediction for one row**, first match: every variant frame zero gives `=0`; a frame-exact class gives `=o`
for an equal series, `<o` for a pointwise-below series of the same length, else `any`; a totals class gives `=o`
for equal sums, `≤o` for a smaller sum, else `any`.

The strongest claim the model makes for that count, within what the class can judge. -/
def predict (exact : Bool) (v o : List Nat) : String :=
  if v.all (· == 0) then "=0"
  else if exact then
    if v == o then "=o"
    else if v.length == o.length && (v.zip o).all (fun p => decide (p.1 ≤ p.2)) then "<o"
    else "any"
  else if v.sum == o.sum then "=o"
  else if v.sum < o.sum then "≤o"
  else "any"

#guard predict true [0, 0] [1, 2] == "=0"
#guard predict true [1, 2] [1, 2] == "=o"
#guard predict true [1, 1] [1, 2] == "<o"
#guard predict true [0, 3] [3, 0] == "any"
#guard predict false [0, 3] [3, 0] == "=o"
#guard predict false [0, 2] [3, 0] == "≤o"
#guard predict false [0, 4] [3, 0] == "any"

/-- The Chromium count types of the swipe profiles (classes from `classes.frozen.json`; `trace.Paint` is
quarantined and left out), as in `morph-mount.jsonl`. Each entry is (name, stage, units, exact).

Which counter reads which stage. -/
def crTypes : List CountType :=
  [⟨"trace.FunctionCall", .script, true, true⟩, ⟨"trace.UpdateLayoutTree", .style, false, true⟩,
   ⟨"trace.Layout", .layout, false, false⟩, ⟨"trace.Layout.dirtyObjects", .layout, true, false⟩,
   ⟨"metric.LayoutCount", .layout, false, false⟩, ⟨"trace.PrePaint", .props, false, false⟩,
   ⟨"raster.invalidationAreaPx", .paint, true, false⟩, ⟨"trace.cc.Commit", .commit, false, true⟩]

/-- The WebKit count types (no frozen classes yet; judged by totals), as in `morph-mount.jsonl`. Each entry is (name, stage, units, exact).

Which counter reads which stage. -/
def wkTypes : List CountType :=
  [⟨"RecalculateStyles", .style, false, false⟩, ⟨"Layout", .layout, false, false⟩,
   ⟨"Paint", .paint, false, false⟩, ⟨"Composite", .commit, false, false⟩]

/-- One JSON row, keys sorted.

The variant flag is `?fw=morph.panel:rest`; the base is the faithful rewrite. -/
def row (engine scenario : String) (t : CountType) (vs os : List Work) : String :=
  "{\"base\":\"rewrite\",\"countType\":\"" ++ t.name ++ "\",\"engine\":\"" ++ engine ++ "\",\"prediction\":\"" ++
    predict t.exact (series vs t) (series os t) ++ "\",\"scenario\":\"" ++ scenario ++ "\",\"stage\":\"" ++
    stageName t.stage ++ "\",\"variant\":\"rewrite+?fw=morph.panel:rest\"}"

/-- All golden rows: Chromium on `swipe-v1` and `swipe-touch-v1`, WebKit on `swipe-v1`.

The list comprehension runs `sc` outer and `t` inner, so there are `2 · 8 + 4 = 20` lines.
The file `packages/contracts/golden/engine/morph-panel.jsonl`, line by line. -/
def goldenLines : List String :=
  (["swipe-v1", "swipe-touch-v1"].flatMap fun sc => crTypes.map fun t => row "chromium" sc t crV crO) ++
    wkTypes.map fun t => row "webkit" "swipe-v1" t wkV wkO

/-- The golden file text: one row per line, trailing newline.

What the driver writes. -/
def goldenText : String := String.join (goldenLines.map (· ++ "\n"))

#guard goldenLines.length == 20
#guard (crTypes.map fun t => predict t.exact (series crV t) (series crO t)) ==
  ["=o", "=o", "any", "any", "any", "=o", "any", "=o"]
#guard (wkTypes.map fun t => predict t.exact (series wkV t) (series wkO t)) == ["=o", "=o", "=o", "=o"]

/-! ## Under the frame-end pass (`frameWorkE`, ledger n=1)

At rest both arms run the same frame `x.f` and differ only in the effect stages the filter adds (`bump`). With one
end-flag assignment `e` for that shared frame, the rest verdicts hold for any base work, so they carry over
unchanged for every `e`. -/

section EndPass

open Fw.Engine.Chromium in
/-- Chromium work of a rest frame under `frameWorkE`, with end flags `e`.

The rest frame's cost with the frame-end pass counted. -/
def crRestWE (F : List FilterOp) (x : RestIn CrProp) (e : Stage → Bool) : Work :=
  if groups F then bump (frameWorkE chromium x.f e) (crEffectStages x) else frameWorkE chromium x.f e

open Fw.Engine.WebKit in
/-- WebKit work of a rest frame under `frameWorkE`, with end flags `e`.

The rest frame's cost with the frame-end pass counted. -/
def wkRestWE (F : List FilterOp) (x : RestIn WkProp) (e : Stage → Bool) : Work :=
  if groups F then bump (frameWorkE webkit x.f e) (wkEffectStages x) else frameWorkE webkit x.f e

/-- **Chromium rest frame under `frameWorkE`: `≤`.**

Dropping `blur(0)` never adds work, end pass or not. -/
theorem cr_rest_leE {r : Rat} (hr : r ≤ 0) (x : RestIn Chromium.CrProp) (e : Stage → Bool) :
    (crRestWE (filterV (fade r)) x e).le (crRestWE (filterO (fade r)) x e) := by
  unfold crRestWE; rw [filterV_rest hr, filterO_rest hr]; exact le_bump _ _

/-- **Chromium rest frame under `frameWorkE`: strict** when the frame has a raster, property or surface step.

The removed effect node saves its unit whatever the end flags. -/
theorem cr_rest_ltE {r : Rat} (hr : r ≤ 0) (x : RestIn Chromium.CrProp) (e : Stage → Bool)
    (hx : x.rasterUnder = true ∨ x.propsPanel = true ∨ x.drawSurface = true) :
    (crRestWE (filterV (fade r)) x e).lt (crRestWE (filterO (fade r)) x e) := by
  unfold crRestWE; rw [filterV_rest hr, filterO_rest hr]
  rcases hx with h | h | h
  · exact lt_bump _ (s := .raster) (by simp [crEffectStages, h])
  · exact lt_bump _ (s := .props) (by simp [crEffectStages, h])
  · exact lt_bump _ (s := .comp) (by simp [crEffectStages, h])

/-- **WebKit rest frame under `frameWorkE`: `≤`.**

The same in Safari. -/
theorem wk_rest_leE {r : Rat} (hr : r ≤ 0) (x : RestIn WebKit.WkProp) (e : Stage → Bool) :
    (wkRestWE (filterV (fade r)) x e).le (wkRestWE (filterO (fade r)) x e) := by
  unfold wkRestWE; rw [filterV_rest hr, filterO_rest hr]; exact le_bump _ _

end EndPass

/-! ## C1 `final-size`: the panel subtree laid out once at the end size, centred in the nav and clipped by it

Refuted on the visual: `hidden_E` and `end_E` hold, `desk_not_Q` and `phone_not_Q` break VisSame on the frames between. -/

namespace FinalSize

open Fw.Engine
open Fw.Parts.Nav (Vp navWidth navHeight navTop panelW panelH pillW pillH phone)
open Fw.Parts.MorphPanel (panelOpacity panelProgress panelScale panelBlurPx)

/-- The two arms: the panel subtree laid out at the nav's size every frame, or once at the end size. -/
inductive Arm where
  | orig
  | final
deriving DecidableEq, Repr

/-- The size the panel subtree is laid out at: the nav box (`inset: 0`) in `orig`, `--panel-w` × `--panel-h` in `final`. -/
def size (a : Arm) (v : Vp) (m : Rat) : Rat × Rat :=
  match a with
  | .orig => (navWidth v false m, navHeight v m)
  | .final => (panelW v, panelH v)

/-- A layout of the panel subtree from its size `(w, h)`: each box's id, border box centred on the panel, own opacity. -/
abbrev Layout := Rat → Rat → List (BoxId × Rect × Rat)

/-- The viewport rectangle. -/
def vpRect (v : Vp) : Rect := ⟨0, 0, v.w, v.h⟩

/-- **One box of the panel subtree on screen** at morph `m`: scaled by the panel's `scale()` about the nav centre, faded
by the panel's opacity and blur, clipped by the nav's padding box. None of this depends on the arm. -/
def place (v : Vp) (m : Rat) (e : BoxId × Rect × Rat) : BoxId × BoxVis :=
  let s := panelScale m
  let W := navWidth v false m
  let H := navHeight v m
  (e.1, ⟨e.2.1, e.2.1, [], ⟨s, 0, 0, s, v.w / 2, navTop v m + H / 2⟩, panelOpacity m * e.2.2,
    some (.rect ⟨-(W / s) / 2, -(H / s) / 2, W / s, H / s⟩), [⟨"blur", [panelBlurPx m]⟩], 0⟩)

/-- **The scene of the panel subtree** in arm `a` at morph `m`: the layout at the arm's size, each box placed by `place`. -/
def scene (L : Layout) (v : Vp) (a : Arm) (m : Rat) : Scene :=
  (L (size a v m).1 (size a v m).2).map (place v m)

/-- Both arms lay out at the same size once the morph is 1. -/
theorem size_end (v : Vp) : size .orig v 1 = size .final v 1 := by
  simp only [size, navWidth, navHeight]; grind

/-- **End frame, E**: at `m = 1` the two scenes are equal, for every layout. -/
theorem end_E (L : Layout) (v : Vp) : scene L v .orig 1 = scene L v .final 1 := by
  unfold scene; rw [size_end]

/-- A scene whose every box has opacity at most 0 shows nothing. -/
theorem visible_alpha_zero (vp : Rect) (s : Scene) (h : ∀ e ∈ s, e.2.alpha ≤ 0) : visible vp s = [] := by
  unfold visible
  rw [List.filter_eq_nil_iff]
  intro e he
  simp [BoxVis.drop, h e he]

/-- **Hidden frames, E**: while `m ≤ 0.08` the panel's opacity is 0, so neither arm shows a box of the subtree. -/
theorem hidden_E (L : Layout) (v : Vp) (a : Arm) {m : Rat} (hm : m ≤ 2 / 25) :
    visible (vpRect v) (scene L v a m) = [] := by
  apply visible_alpha_zero
  intro e he
  simp only [scene, List.mem_map] at he
  obtain ⟨x, -, rfl⟩ := he
  simp [place, panelOpacity, Fw.Parts.MorphPanel.panelProgress_zero m hm]

/-- The arms' layout sizes differ by `(1 - m)` times the morph's whole growth. -/
theorem size_gap (v : Vp) (m : Rat) :
    (size .final v m).1 - (size .orig v m).1 = (1 - m) * (panelW v - pillW v) ∧
      (size .final v m).2 - (size .orig v m).2 = (1 - m) * (panelH v - pillH v) := by
  simp only [size, navWidth, navHeight]; constructor <;> grind

/-- The bounding box of a centred rectangle under a positive scale about the origin and a translation. -/
theorem bbox_centred (s e f w h : Rat) (hs : 0 < s) (hw : 0 < w) (hh : 0 < h) :
    Affine.bbox ⟨s, 0, 0, s, e, f⟩ ⟨-w / 2, -h / 2, w, h⟩ = ⟨e - s * w / 2, f - s * h / 2, s * w, s * h⟩ := by
  have hsw : 0 < s * w := Rat.mul_pos hs hw
  have hsh : 0 < s * h := Rat.mul_pos hs hh
  simp only [Affine.bbox, Affine.apply, Rect.mk.injEq]
  refine ⟨?_, ?_, ?_, ?_⟩ <;> grind

/-- `--col-offset` of the five columns, as a fraction of the column's own height (morph.columns `data.ts`). -/
def colOffsets : List Rat := [-3 / 10, -33 / 100, -19 / 100, -33 / 100, -11 / 100]

/-- Columns shown: 3 at `width ≤ 640px`, else 5 (morph.columns `:nth-child(n + 4) { display: none }`). -/
def ncols (v : Vp) : Nat := if phone v.w then 3 else 5

/-- The backdrop's gap: 8px at `width ≤ 640px`, else 12px. -/
def colGap (v : Vp) : Rat := if phone v.w then 8 else 12

/-- A column's width: the backdrop (`inset: 0 -3%`, so 1.06 × the panel) less the gaps, shared by `flex: 1 1 0`. -/
def colW (v : Vp) (w : Rat) : Rat := ((53 / 50) * w - ((ncols v : Rat) - 1) * colGap v) / ncols v

/-- The footer's height: 68px (`height: 68px`; at `width ≤ 640px` its one visible row, 20px, plus 24px padding twice). -/
def footerH : Rat := 68

/-- The veil at panel size `(w, h)`. -/
def veil (w h : Rat) : BoxId × Rect × Rat := ("veil", Rect.mk (-w / 2) (-h / 2) w h, 1)

/-- The columns of the backdrop at panel size `(w, h)`. -/
def cols (v : Vp) (w h : Rat) : List (BoxId × Rect × Rat) :=
  (colOffsets.take (ncols v)).zipIdx.map fun (o, i) =>
    (s!"col{i}", Rect.mk (-(53 / 100) * w + i * (colW v w + colGap v)) (-h / 2 + o * h) (colW v w) h, 2 / 5)

/-- The footer at panel size `(w, h)`. -/
def footer (w h : Rat) : BoxId × Rect × Rat := ("footer", Rect.mk (-w / 2) (h / 2 - footerH) w footerH, 1)

/-- **The panel subtree's size-dependent boxes** in paint order: the veil (`inset: 0`), the columns (`flex: 1 1 0`,
translated by `--col-offset` of their own height), the footer (`bottom: 0`). Coordinates are centred on the panel. -/
def subtree (v : Vp) : Layout := fun w h => veil w h :: (cols v w h ++ [footer w h])

/-- **Footer shift**: the `final` arm draws the footer `(1 - m)` half the height growth lower, below the nav's clip. -/
theorem footer_shift (v : Vp) (m : Rat) :
    (footer (size .final v m).1 (size .final v m).2).2.1.y - (footer (size .orig v m).1 (size .orig v m).2).2.1.y =
      (1 - m) * (panelH v - pillH v) / 2 := by
  have := (size_gap v m).2
  simp only [footer]; grind

/-- **Frames between, not Q**: while the panel is visible and the arms' heights differ by more than ½ px, the veil,
first in paint order, is kept in both arms and its box height differs beyond PL1. -/
theorem not_Q (v : Vp) (m : Rat) (hα : 0 < panelOpacity m) (hs : 0 < panelScale m) (hW : 0 < navWidth v false m)
    (hH : 0 < navHeight v m) (hWf : 0 < panelW v) (hHf : 0 < panelH v) (hcx : 0 < v.w)
    (hcy0 : 0 < navTop v m + navHeight v m / 2) (hcy1 : navTop v m + navHeight v m / 2 < v.h)
    (hgap : 1 / 2 < (1 - m) * (panelH v - pillH v)) :
    ¬ Q (visible (vpRect v) (scene (subtree v) v .orig m)) (visible (vpRect v) (scene (subtree v) v .final m)) := by
  have kept : ∀ a : Arm, 0 < (size a v m).1 → 0 < (size a v m).2 →
      visible (vpRect v) (scene (subtree v) v a m) =
        place v m (veil (size a v m).1 (size a v m).2) ::
          visible (vpRect v) ((cols v (size a v m).1 (size a v m).2 ++
            [footer (size a v m).1 (size a v m).2]).map (place v m)) := by
    intro a hw hh
    have hsw := Rat.mul_pos hs hw
    have hsh := Rat.mul_pos hs hh
    have hWs : 0 < navWidth v false m / panelScale m := by
      rw [Rat.div_def]; exact Rat.mul_pos hW (Rat.inv_pos.mpr hs)
    have hHs : 0 < navHeight v m / panelScale m := by
      rw [Rat.div_def]; exact Rat.mul_pos hH (Rat.inv_pos.mpr hs)
    simp only [scene, subtree, List.map_cons, visible, List.filter_cons]
    rw [ite_eq_left]
    simp only [place, veil, BoxVis.drop, bbox_centred _ _ _ _ _ hs hw hh, Rect.meets, vpRect, List.lookup]
    have h1 : ¬ panelOpacity m * 1 ≤ 0 := by grind
    simp; grind
  have hfar : Fw.Gate.near Fw.Gate.tolBox (size .orig v m).2 (size .final v m).2 = false := by
    have := (size_gap v m).2
    simp only [Fw.Gate.near, Fw.Gate.tolBox, Bool.and_eq_false_iff]
    grind
  intro hq
  unfold Q at hq
  rw [kept .orig hW hH, kept .final hWf hHf] at hq
  simp [sceneQ, boxQ, nearRect, place, veil, hfar] at hq

/-- The desktop viewport of the lag note, 1440 × 900. -/
def desk : Vp := ⟨1440, 900⟩

/-- The phone viewport of the lag note, 390 × 844. -/
def phoneVp : Vp := ⟨390, 844⟩

/-- The nav sizes at 1440 × 900. -/
theorem desk_vals : pillW desk = 984 ∧ pillH desk = 64 ∧ panelW desk = 1398 ∧ panelH desk = 820 ∧
    phone desk.w = false := by decide +kernel

/-- The nav sizes at 390 × 844. -/
theorem phone_vals : pillW phoneVp = 358 ∧ pillH phoneVp = 52 ∧ panelW phoneVp = 366 ∧ panelH phoneVp = 820 ∧
    phone phoneVp.w = true := by decide +kernel

/-- The panel is visible exactly past `m = 0.08`. -/
theorem opacity_pos {m : Rat} (h : 2 / 25 < m) : 0 < panelOpacity m := by
  simp only [panelOpacity, panelProgress, Fw.Parts.MorphPanel.clamp01]; grind

/-- **Desktop, not Q**: every morph value in `(0.08, 1 - 1/1512)` breaks VisSame at 1440 × 900. -/
theorem desk_not_Q {m : Rat} (h0 : 2 / 25 < m) (h1 : m < 1 - 1 / 1512) :
    ¬ Q (visible (vpRect desk) (scene (subtree desk) desk .orig m))
      (visible (vpRect desk) (scene (subtree desk) desk .final m)) := by
  obtain ⟨hpw, hph, hw, hh, hp⟩ := desk_vals
  apply not_Q desk m (opacity_pos h0)
  all_goals (try simp only [panelScale, navWidth, navHeight, navTop, hpw, hph, hw, hh, hp])
  all_goals (try simp only [desk])
  all_goals grind

/-- **Phone, not Q**: every morph value in `(0.08, 1 - 1/1536)` breaks VisSame at 390 × 844. -/
theorem phone_not_Q {m : Rat} (h0 : 2 / 25 < m) (h1 : m < 1 - 1 / 1536) :
    ¬ Q (visible (vpRect phoneVp) (scene (subtree phoneVp) phoneVp .orig m))
      (visible (vpRect phoneVp) (scene (subtree phoneVp) phoneVp .final m)) := by
  obtain ⟨hpw, hph, hw, hh, hp⟩ := phone_vals
  apply not_Q phoneVp m (opacity_pos h0)
  all_goals (try simp only [panelScale, navWidth, navHeight, navTop, hpw, hph, hw, hh, hp])
  all_goals (try simp only [phoneVp])
  all_goals grind

/-- The morph value of tween frame `k` at 60 Hz after a push from `f` to `t`. -/
def frameM (f t : Rat) (k : Nat) : Rat := (Fw.Parts.MorphTween.tween f t ((k : Rat) * (50 / 3))).value

/-- **The verdict of one frame**: `E` when the visible scenes are equal, `Q` within the gate's tolerances, else `differs`. -/
def verdict (v : Vp) (m : Rat) : String :=
  let o := visible (vpRect v) (scene (subtree v) v .orig m)
  let f := visible (vpRect v) (scene (subtree v) v .final m)
  if o == f then "E" else if sceneQ o f then "Q" else "differs"

/-- The frames `0 … 41` of one push with the verdict `differs`. -/
def differing (v : Vp) (f t : Rat) : List Nat := (List.range 42).filter fun k => verdict v (frameM f t k) == "differs"

/-- The 42 frames of one push from `f` to `t`. -/
def frames (f t : Rat) : List Rat := (List.range 42).map (frameM f t)

/-- **Panel subtree layouts in one run**: the frame pairs whose layout size changes, each a relayout of panel and columns. -/
def relayouts (a : Arm) (v : Vp) (ms : List Rat) : Nat :=
  ((ms.zip ms.tail).filter fun p => size a v p.1 != size a v p.2).length

/-- **Work bound**: the `final` arm lays out the panel subtree in no frame of any run. -/
theorem relayouts_final (v : Vp) (ms : List Rat) : relayouts .final v ms = 0 := by
  simp [relayouts, size]

/-- The `orig` arm lays out the panel subtree again on every frame whose morph value changes. -/
theorem relayouts_orig_pos (v : Vp) {m n : Rat} (hmn : m ≠ n) (hH : pillH v ≠ panelH v) :
    relayouts .orig v [m, n] = 1 := by
  have : navHeight v m ≠ navHeight v n := by
    simp only [navHeight]; intro h; apply hmn
    have h2 : (panelH v - pillH v) * (m - n) = 0 := by grind
    rcases Rat.mul_eq_zero.mp h2 with h3 | h3 <;> grind
  simp [relayouts, size, this]

#guard relayouts .orig desk (frames 0 1) = 41
#guard relayouts .orig phoneVp (frames 0 1) = 41
#guard relayouts .final desk (frames 0 1) = 0
#guard (List.range 42).map (fun k => verdict desk (frameM 0 1 k)) =
  ["E", "E"] ++ List.replicate 36 "differs" ++ ["Q", "Q", "Q", "E"]
#guard differing desk 0 1 = (List.range 36).map (· + 2)
#guard differing phoneVp 0 1 = (List.range 36).map (· + 2)
#guard differing desk 1 0 = (List.range 23).map (· + 1)
#guard differing phoneVp 1 0 = (List.range 23).map (· + 1)
#guard verdict desk 0 = "E" && verdict desk 1 = "E" && verdict desk (1 / 2) = "differs"

end FinalSize

end Fw.Parts.MorphPanelOpt
