import Lean.Data.Json
import Fw.Engine.Chromium
import Fw.Engine.WebKit
import Fw.Engine.Visual
import Fw.Parts.EndFlags
import Fw.Engine.Lessons
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

$$\forall r \in \mathbb{Q}:\ \operatorname{fade}(r) = 1 - \min\!\big(1,\ \tfrac{20}{11}\, r\big)$$

The panel's fade value from the section progress `r`. -/
def fade (r : Rat) : Rat := 1 - min 1 (r * (20/11))

/-- **The blur radius in px** of `blur(calc((1 - φ) * 12px))`; `calc()` clamps a negative length to 0.

$$\forall \varphi \in \mathbb{Q}:\ \operatorname{radius}(\varphi) = \max\!\big(0,\ (1 - \varphi) \cdot 12\big)$$

The blur radius for fade value `φ`. -/
def radius (φ : Rat) : Rat := max 0 ((1 - φ) * 12)

/-- One `blur(x)` filter operation.

$$\forall x \in \mathbb{Q}:\ \operatorname{blurOp}(x) = (\texttt{"blur"}, [x])$$

The computed filter function `blur(x px)`. -/
def blurOp (x : Rat) : FilterOp := ⟨"blur", [x]⟩

/-- **The original's filter list**: always one blur, `blur(0)` included.

$$\forall \varphi \in \mathbb{Q}:\ F_o(\varphi) = [\operatorname{blurOp}(\operatorname{radius}(\varphi))]$$

The original never drops the filter. -/
def filterO (φ : Rat) : List FilterOp := [blurOp (radius φ)]

/-- **The variant's filter list** (decision function): `none` when the radius is 0, else the original's blur.

$$\forall \varphi \in \mathbb{Q}:\ F_v(\varphi) = \begin{cases} [\,] & \operatorname{radius}(\varphi) = 0 \\ F_o(\varphi) & \text{otherwise} \end{cases}$$

The variant writes `filter: none` at rest and the same blur otherwise. -/
def filterV (φ : Rat) : List FilterOp := if radius φ = 0 then [] else filterO φ

#guard fade 0 == 1 && fade (11/20) == 0 && fade (11/40) == 1/2 && fade (-1) == 31/11 && fade 2 == 0
#guard radius 1 == 0 && radius (1/2) == 6 && radius 0 == 12 && radius 2 == 0
#guard filterV 1 == [] && filterO 1 == [⟨"blur", [0]⟩]
#guard filterV (1/2) == [⟨"blur", [6]⟩] && filterV (1/2) == filterO (1/2)
#guard filterV (fade (-3)) == [] && filterV (fade (1/100)) != []

/-- The radius is 0 exactly when the fade is at least 1.

$$\forall \varphi \in \mathbb{Q}:\ \operatorname{radius}(\varphi) = 0 \iff 1 \le \varphi$$

No blur exactly at full fade. -/
theorem radius_eq_zero_iff (φ : Rat) : radius φ = 0 ↔ 1 ≤ φ := by
  unfold radius; grind

/-- The fade is at least 1 exactly when the progress is at most 0.

$$\forall r \in \mathbb{Q}:\ 1 \le \operatorname{fade}(r) \iff r \le 0$$

Full fade exactly at rest. -/
theorem fade_ge_one_iff (r : Rat) : 1 ≤ fade r ↔ r ≤ 0 := by
  unfold fade; grind

/-- **Rest is exactly `r ≤ 0`**: the blur radius is 0 exactly when the progress is at most 0.

$$\forall r \in \mathbb{Q}:\ \operatorname{radius}(\operatorname{fade}(r)) = 0 \iff r \le 0$$

The panel is unblurred exactly at rest. -/
theorem rest_iff (r : Rat) : radius (fade r) = 0 ↔ r ≤ 0 :=
  (radius_eq_zero_iff _).trans (fade_ge_one_iff r)

/-- At rest the original's filter is `blur(0)`.

$$\forall r \in \mathbb{Q}:\ r \le 0 \Rightarrow F_o(\operatorname{fade}(r)) = [\operatorname{blurOp}(0)]$$

The original keeps a zero blur at rest. -/
theorem filterO_rest {r : Rat} (h : r ≤ 0) : filterO (fade r) = [blurOp 0] := by
  simp only [filterO, (rest_iff r).mpr h]

/-- At rest the variant's filter is `none`.

$$\forall r \in \mathbb{Q}:\ r \le 0 \Rightarrow F_v(\operatorname{fade}(r)) = [\,]$$

The variant drops the filter at rest. -/
theorem filterV_rest {r : Rat} (h : r ≤ 0) : filterV (fade r) = [] := by
  simp only [filterV, (rest_iff r).mpr h, ↓reduceIte]

/-- During the fade both arms carry the same blur.

$$\forall r \in \mathbb{Q}:\ 0 < r \Rightarrow F_v(\operatorname{fade}(r)) = F_o(\operatorname{fade}(r))$$

Outside rest the variant changes nothing in the filter. -/
theorem filterV_fade {r : Rat} (h : 0 < r) : filterV (fade r) = filterO (fade r) := by
  have : radius (fade r) ≠ 0 := fun h0 => absurd ((rest_iff r).mp h0) (by grind)
  simp only [filterV, this, ↓reduceIte]

/-! ## (vis): the scene -/

/-- An identity filter operation: `blur(0)`.

$$\forall (n, a) \in \mathrm{FilterOp}:\ \operatorname{identity}(n, a) \iff n = \texttt{"blur"} \land a = [0]$$

A filter function that leaves every pixel as it is. -/
def identityOp (op : FilterOp) : Bool := op.name == "blur" && op.args == [0]

/-- **The filter the rasterizer applies**: the list without identity operations. WebKit skips an identity list
(`RenderLayer.cpp:1062`, CONFIRMED); Chromium replays `blur(0)` as a `SaveLayer` whose blur of radius 0 returns its
input (INFERRED from Skia; a `SaveLayer` can drop LCD text, excluded by PLAN H1).

$$\forall F \in \mathrm{FilterOp}^{*}:\ \operatorname{render}(F) = [\, f \in F \mid \neg \operatorname{identity}(f) \,]$$

What the filter does to pixels. -/
def render (F : List FilterOp) : List FilterOp := F.filter fun op => !identityOp op

/-- **The containing-block and stacking-context channel** (R10): a non-`none` filter list, `blur(0)` included,
makes the panel a containing block for absolute and fixed descendants and a stacking context.

$$\forall F \in \mathrm{FilterOp}^{*}:\ \operatorname{groups}(F) \iff F \ne [\,]$$

Whether the filter changes how descendants are placed and stacked. -/
def groups (F : List FilterOp) : Bool := !F.isEmpty

#guard render [blurOp 0] == [] && render [blurOp 3] == [blurOp 3] && render [] == []
#guard groups [blurOp 0] && !groups []

/-- **The original's scene**: a part-independent builder fed the applied filter and the group bit of `F_o`.

$$\forall \mathit{build}, r, \mathit{env}, t:\ \operatorname{scene}_o(\mathit{env}, t) = \mathit{build}\big(\mathit{env}, t, \operatorname{render}(F_o(\operatorname{fade}(r(\mathit{env}, t)))), \operatorname{groups}(F_o(\operatorname{fade}(r(\mathit{env}, t))))\big)$$

The page as the original draws it. -/
def sceneO {Env T : Type} (build : Env → T → List FilterOp → Bool → Scene) (r : Env → T → Rat) (env : Env)
    (t : T) : Scene :=
  build env t (render (filterO (fade (r env t)))) (groups (filterO (fade (r env t))))

/-- **The variant's scene**: the same builder fed the applied filter and the group bit of `F_v`.

$$\forall \mathit{build}, r, \mathit{env}, t:\ \operatorname{scene}_v(\mathit{env}, t) = \mathit{build}\big(\mathit{env}, t, \operatorname{render}(F_v(\operatorname{fade}(r(\mathit{env}, t)))), \operatorname{groups}(F_v(\operatorname{fade}(r(\mathit{env}, t))))\big)$$

The page as the variant draws it. -/
def sceneV {Env T : Type} (build : Env → T → List FilterOp → Bool → Scene) (r : Env → T → Rat) (env : Env)
    (t : T) : Scene :=
  build env t (render (filterV (fade (r env t)))) (groups (filterV (fade (r env t))))

/-- **Premise RG10** (R10): at every rest instant, the scene does not depend on whether the panel is a containing
block and a stacking context, i.e. no descendant is `position: fixed` or absolutely positioned against the panel,
and the z-indexed descendants stack the same (checked by PL0/PL2, not assumed).

$$\operatorname{RG10}(\mathit{build}, r) \iff \forall \mathit{env}, t:\ r(\mathit{env}, t) \le 0 \Rightarrow \mathit{build}(\mathit{env}, t, [\,], \mathrm{true}) = \mathit{build}(\mathit{env}, t, [\,], \mathrm{false})$$

Dropping the containing block and stacking context at rest changes nothing visible. -/
def RG10 {Env T : Type} (build : Env → T → List FilterOp → Bool → Scene) (r : Env → T → Rat) : Prop :=
  ∀ env t, r env t ≤ 0 → build env t [] true = build env t [] false

/-- **The channel RG10 closes is real**: at rest the original's filter groups and the variant's does not.

$$\forall r \in \mathbb{Q}:\ r \le 0 \Rightarrow \operatorname{groups}(F_o(\operatorname{fade}(r))) = \mathrm{true} \land \operatorname{groups}(F_v(\operatorname{fade}(r))) = \mathrm{false}$$

Without RG10 the variant could move or restack a descendant. -/
theorem rest_groups_differ {r : Rat} (h : r ≤ 0) :
    groups (filterO (fade r)) = true ∧ groups (filterV (fade r)) = false := by
  rw [filterO_rest h, filterV_rest h]; decide

/-- **During the fade the scenes are equal**, with no premise.

$$\forall \mathit{build}, r, \mathit{env}, t:\ 0 < r(\mathit{env}, t) \Rightarrow \operatorname{scene}_o(\mathit{env}, t) = \operatorname{scene}_v(\mathit{env}, t)$$

Outside rest the variant draws exactly what the original draws. -/
theorem fade_scene_eq {Env T : Type} (build : Env → T → List FilterOp → Bool → Scene) (r : Env → T → Rat)
    (env : Env) (t : T) (h : 0 < r env t) : sceneO build r env t = sceneV build r env t := by
  simp only [sceneO, sceneV, filterV_fade h]

/-- **(vis) at rest, class E**: under RG10, the visible scenes are equal in every environment (every width band)
and at every instant.

$$\forall \mathit{build}, r, \mathit{vp}:\ \operatorname{RG10}(\mathit{build}, r) \Rightarrow \forall \mathit{env}, t:\ \operatorname{visible}_{\mathit{vp}(\mathit{env})}(\operatorname{scene}_o(\mathit{env}, t)) = \operatorname{visible}_{\mathit{vp}(\mathit{env})}(\operatorname{scene}_v(\mathit{env}, t))$$

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

$$\forall \mathit{build}, r, \mathit{vp}:\ \operatorname{RG10}(\mathit{build}, r) \Rightarrow \forall \mathit{env}, t:\ \operatorname{visible}_{\mathit{vp}(\mathit{env})}(\operatorname{scene}_o(\mathit{env}, t)) \approx_Q \operatorname{visible}_{\mathit{vp}(\mathit{env})}(\operatorname{scene}_v(\mathit{env}, t))$$

Up to the gate's tolerances, the own-layer fade looks the same. -/
theorem fade_visSame_Q {Env T : Type} (build : Env → T → List FilterOp → Bool → Scene) (r : Env → T → Rat)
    (vp : Env → Rect) (h : RG10 build r) : VisSame Q vp (sceneO build r) (sceneV build r) :=
  visSame_E_Q (rest_visSame_E build r vp h)

/-! ## (work): the effect overlay -/

/-- **Extra work on given stages**: each listed stage runs (at least once) and gets one more unit.

$$\forall w, S:\ \operatorname{bump}(w, S) = \Big(s \mapsto \max\!\big(w.\mathrm{passes}(s), [s \in S]\big),\ s \mapsto w.\mathrm{units}(s) + [s \in S],\ w.\mathrm{hits}\Big)$$

One more operation on each stage in the list. -/
def bump (w : Work) (ss : List Stage) : Work where
  passes s := max (w.passes s) (if s ∈ ss then 1 else 0)
  units s := w.units s + (if s ∈ ss then 1 else 0)
  hits := w.hits

/-- Bumping never lowers work.

$$\forall w, S:\ w \preceq \operatorname{bump}(w, S)$$

Extra work is extra. -/
theorem le_bump (w : Work) (ss : List Stage) : w.le (bump w ss) :=
  ⟨fun _ => ⟨Nat.le_max_left _ _, Nat.le_add_right _ _⟩, Nat.le_refl _⟩

/-- Bumping a stage is strictly more.

$$\forall w, S, s:\ s \in S \Rightarrow w \prec \operatorname{bump}(w, S)$$

One more unit on a listed stage. -/
theorem lt_bump (w : Work) {ss : List Stage} {s : Stage} (hs : s ∈ ss) : w.lt (bump w ss) :=
  ⟨le_bump w ss, Or.inl ⟨s, Or.inr (by simp [bump, hs])⟩⟩

/-- **One rest frame**: the frame's own changes (no panel-level change at rest, as `--morph-fade` stays `1`), and
three facts about it: content painted in the panel's own chunks is rastered (`rasterUnder`), the panel's paint
properties are updated (`propsPanel`), the compositor draws while the panel has composited descendants
(`drawSurface`).

$$\mathrm{RestIn}(P) = \mathrm{FrameIn}(P) \times \mathbb{B}^3$$

What happens in a rest frame besides the panel's filter. -/
structure RestIn (P : Type) where
  f : FrameIn P
  rasterUnder : Bool
  propsPanel : Bool
  drawSurface : Bool

/-- **The Chromium effect-node stages** of a rest frame: the `SaveLayer` replay on raster, the effect node's
property update, the render-surface draw (cites in the module doc).

$$\forall x:\ S_{\mathrm{cr}}(x) = [\mathrm{raster} \mid x.\mathrm{rasterUnder}] \mathbin{+\!\!+} [\mathrm{props} \mid x.\mathrm{propsPanel}] \mathbin{+\!\!+} [\mathrm{comp} \mid x.\mathrm{drawSurface}]$$

The work Chromium's effect node adds to a frame. -/
def crEffectStages {P : Type} (x : RestIn P) : List Stage :=
  (if x.rasterUnder then [.raster] else []) ++ (if x.propsPanel then [.props] else []) ++
    (if x.drawSurface then [.comp] else [])

/-- **The WebKit effect stages** of a rest frame: `blur(0)` is an identity and is not painted, so only the compositor
draw of the indirectly composited panel layer remains (the layer exists, CONFIRMED; its per-frame draw, INFERRED).

$$\forall x:\ S_{\mathrm{wk}}(x) = [\mathrm{comp} \mid x.\mathrm{drawSurface}]$$

The work WebKit's filter group adds to a frame. -/
def wkEffectStages {P : Type} (x : RestIn P) : List Stage := if x.drawSurface then [.comp] else []

open Fw.Engine.Chromium in
/-- **Chromium work of a rest frame** with filter list `F`: the frame's work, plus the effect stages when `F` is
non-empty (`HasFilter`).

$$\forall F, x:\ W_{\mathrm{cr}}(F, x) = \begin{cases} \operatorname{bump}(\operatorname{frameWork}_{\mathrm{chromium}}(x.f), S_{\mathrm{cr}}(x)) & F \ne [\,] \\ \operatorname{frameWork}_{\mathrm{chromium}}(x.f) & F = [\,] \end{cases}$$

What a rest frame costs in Chromium. -/
def crRestW (F : List FilterOp) (x : RestIn CrProp) : Work :=
  if groups F then bump (frameWork chromium x.f) (crEffectStages x) else frameWork chromium x.f

open Fw.Engine.WebKit in
/-- **WebKit work of a rest frame** with filter list `F`: the frame's work, plus the effect stages when `F` is not
`none` (`hasFilter`).

$$\forall F, x:\ W_{\mathrm{wk}}(F, x) = \begin{cases} \operatorname{bump}(\operatorname{frameWork}_{\mathrm{webkit}}(x.f), S_{\mathrm{wk}}(x)) & F \ne [\,] \\ \operatorname{frameWork}_{\mathrm{webkit}}(x.f) & F = [\,] \end{cases}$$

What a rest frame costs in WebKit. -/
def wkRestW (F : List FilterOp) (x : RestIn WkProp) : Work :=
  if groups F then bump (frameWork webkit x.f) (wkEffectStages x) else frameWork webkit x.f

/-! ## (work) at rest: dominance -/

/-- **(work) at rest, Chromium, per frame**: the variant is at most the original.

$$\forall r \in \mathbb{Q},\ \forall x:\ r \le 0 \Rightarrow W_{\mathrm{cr}}(F_v(\operatorname{fade}(r)), x) \preceq W_{\mathrm{cr}}(F_o(\operatorname{fade}(r)), x)$$

Dropping `blur(0)` never adds Chromium work in a rest frame. -/
theorem cr_rest_le {r : Rat} (hr : r ≤ 0) (x : RestIn Chromium.CrProp) :
    (crRestW (filterV (fade r)) x).le (crRestW (filterO (fade r)) x) := by
  rw [filterV_rest hr, filterO_rest hr]; exact le_bump _ _

/-- **(work) at rest, Chromium, strict**: one fewer `SaveLayer` replay, effect-node update or render-surface draw
whenever the frame has one.

$$\forall r \in \mathbb{Q},\ \forall x:\ r \le 0 \land (x.\mathrm{rasterUnder} \lor x.\mathrm{propsPanel} \lor x.\mathrm{drawSurface}) \Rightarrow W_{\mathrm{cr}}(F_v(\operatorname{fade}(r)), x) \prec W_{\mathrm{cr}}(F_o(\operatorname{fade}(r)), x)$$

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

$$\forall r \in \mathbb{Q},\ \forall x:\ r \le 0 \Rightarrow W_{\mathrm{wk}}(F_v(\operatorname{fade}(r)), x) \preceq W_{\mathrm{wk}}(F_o(\operatorname{fade}(r)), x)$$

Dropping `blur(0)` never adds WebKit work in a rest frame. -/
theorem wk_rest_le {r : Rat} (hr : r ≤ 0) (x : RestIn WebKit.WkProp) :
    (wkRestW (filterV (fade r)) x).le (wkRestW (filterO (fade r)) x) := by
  rw [filterV_rest hr, filterO_rest hr]; exact le_bump _ _

/-- **(work) at rest, WebKit, strict**: one fewer compositor draw of the indirect panel layer in every frame the
compositor draws it. Painting saves nothing (`blur(0)` is an identity).

$$\forall r \in \mathbb{Q},\ \forall x:\ r \le 0 \land x.\mathrm{drawSurface} \Rightarrow W_{\mathrm{wk}}(F_v(\operatorname{fade}(r)), x) \prec W_{\mathrm{wk}}(F_o(\operatorname{fade}(r)), x)$$

WebKit's only per-frame saving is the compositor draw. -/
theorem wk_rest_lt {r : Rat} (hr : r ≤ 0) (x : RestIn WebKit.WkProp) (hx : x.drawSurface = true) :
    (wkRestW (filterV (fade r)) x).lt (wkRestW (filterO (fade r)) x) := by
  rw [filterV_rest hr, filterO_rest hr]
  exact lt_bump _ (s := .comp) (by simp [wkEffectStages, hx])

/-- Pointwise `≤` lifts to aligned runs.

$$\forall g, h : \alpha \to \mathrm{Work}:\ (\forall x:\ g(x) \preceq h(x)) \Rightarrow \forall X \in \alpha^{*}:\ \operatorname{leAll}(\operatorname{map}(g, X), \operatorname{map}(h, X)) = \mathrm{true}$$

Frame-by-frame order gives run order. -/
theorem leAll_map {α : Type} (g h : α → Work) (hle : ∀ x, (g x).le (h x)) :
    ∀ xs : List α, leAll (xs.map g) (xs.map h) = true
  | [] => rfl
  | x :: xs => by
    simp only [List.map_cons, leAll, Bool.and_eq_true]
    exact ⟨(Work.leb_iff _ _).mpr (hle x), leAll_map g h hle xs⟩

/-- One strictly smaller frame makes `someLt` true.

$$\forall g, h : \alpha \to \mathrm{Work},\ \forall X \in \alpha^{*}:\ (\exists x \in X:\ g(x) \prec h(x)) \Rightarrow \operatorname{someLt}(\operatorname{map}(g, X), \operatorname{map}(h, X)) = \mathrm{true}$$

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

$$\forall r \in \mathbb{Q},\ \forall X,\ \forall \rho \in \mathrm{Resident}:\ r \le 0 \land \big(\exists x \in X:\ x.\mathrm{rasterUnder} \lor x.\mathrm{propsPanel} \lor x.\mathrm{drawSurface}\big) \Rightarrow \operatorname{claim}\big(\operatorname{screen}(\operatorname{toRun}(\operatorname{map}(W_{\mathrm{cr}}(F_o(\operatorname{fade}(r)), \cdot), X)), \operatorname{toRun}(\operatorname{map}(W_{\mathrm{cr}}(F_v(\operatorname{fade}(r)), \cdot), X))), \rho, \rho\big) = \mathrm{dominates}$$

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

$$\forall F, d, \rho, k:\ \operatorname{res}_{\mathrm{wk}}(F, d, \rho, k) = \begin{cases} (\rho.\mathrm{layers} + 1,\ \rho.\mathrm{backingKpx} + k) & F \ne [\,] \land d \\ \rho & \text{otherwise} \end{cases}$$

What the panel's filter keeps resident in WebKit. -/
def wkResident (F : List FilterOp) (desc : Bool) (res : Resident) (kpx : Nat) : Resident :=
  if groups F && desc then ⟨res.layers + 1, res.backingKpx + kpx⟩ else res

/-- **WebKit at rest: one fewer composited layer** when the panel has composited descendants.

$$\forall r \in \mathbb{Q},\ \forall d, \rho, k:\ r \le 0 \Rightarrow \operatorname{res}_{\mathrm{wk}}(F_v(\operatorname{fade}(r)), d, \rho, k).\mathrm{layers} + [d] = \operatorname{res}_{\mathrm{wk}}(F_o(\operatorname{fade}(r)), d, \rho, k).\mathrm{layers}$$

Dropping `blur(0)` frees the indirect layer. -/
theorem wk_rest_layers {r : Rat} (hr : r ≤ 0) (desc : Bool) (res : Resident) (kpx : Nat) :
    (wkResident (filterV (fade r)) desc res kpx).layers + (if desc then 1 else 0) =
      (wkResident (filterO (fade r)) desc res kpx).layers := by
  rw [filterV_rest hr, filterO_rest hr]; cases desc <;> rfl

/-- **(work) at rest, WebKit, per run: dominates**, with the resident state not growing (it shrinks with composited
descendants).

$$\forall r \in \mathbb{Q},\ \forall X, d, \rho, k:\ r \le 0 \land (\exists x \in X:\ x.\mathrm{drawSurface}) \Rightarrow \operatorname{claim}\big(\operatorname{screen}(\operatorname{toRun}(\operatorname{map}(W_{\mathrm{wk}}(F_o(\operatorname{fade}(r)), \cdot), X)), \operatorname{toRun}(\operatorname{map}(W_{\mathrm{wk}}(F_v(\operatorname{fade}(r)), \cdot), X))), \operatorname{res}_{\mathrm{wk}}(F_v(\operatorname{fade}(r)), d, \rho, k), \operatorname{res}_{\mathrm{wk}}(F_o(\operatorname{fade}(r)), d, \rho, k)\big) = \mathrm{dominates}$$

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

$$\mathrm{panel} = 0$$

The `.start-selling-platform` box. -/
def panel : Nat := 0

open Fw.Engine.WebKit in
/-- **Why the rest win needs no panel-level change at rest** (`wk_not_mono`): an opacity change on the panel is a
recomposite on the original's indirectly composited layer but a layer repaint on the variant's non-composited layer,
so the variant's frame is not below the original's.

$$\neg\Big(\operatorname{frameWork}_{\mathrm{webkit}}(\operatorname{jsFrame}[(\mathrm{panel}, \mathrm{opacity}, \mathrm{layer})]) \preceq \operatorname{frameWork}_{\mathrm{webkit}}(\operatorname{jsFrame}[(\mathrm{panel}, \mathrm{opacity}, \mathrm{own})])\Big)$$

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

$$\forall f, S:\ \mathrm{layout} \notin S \land \operatorname{frameWork}_{\mathrm{chromium}}(f).\mathrm{passes}(\mathrm{layout}) = 0 \Rightarrow \neg\Big(\operatorname{bump}(\operatorname{frameWork}_{\mathrm{chromium}}(f), \operatorname{stages}(\mathrm{layoutFull})) \preceq \operatorname{bump}(\operatorname{frameWork}_{\mathrm{chromium}}(f), S)\Big)$$

The flip frame costs a layout the original never pays. -/
theorem cr_toggle_not_le (f : FrameIn CrProp) (ss : List Stage) (hs : Stage.layout ∉ ss)
    (h0 : (frameWork chromium f).passes .layout = 0) :
    ¬ (bump (frameWork chromium f) CrLevel.layoutFull.stages).le (bump (frameWork chromium f) ss) := by
  intro h
  have := (h.1 .layout).1
  simp [bump, hs, h0, CrLevel.stages] at this

/-- The custom property the script writes (part-local id).

$$\mathrm{fadeVar} = 0$$

`--morph-fade`. -/
def fadeVar : Nat := 0

open Fw.Engine.Chromium in
/-- **The `--morph-fade` write** in Chromium: a custom property read by `filter` (a blur) and `opacity`.

$$\mathrm{fadeProp} = \operatorname{custom}(\mathrm{fadeVar}, [\operatorname{filter}(\mathrm{true}), \mathrm{opacity}])$$

One fade step as Chromium sees it. -/
def fadeProp : CrProp := .custom fadeVar [.filter true, .opacity]

open Fw.Engine.Chromium in
/-- **A fade frame in Chromium**: one script callback that writes `--morph-fade` on the panel in layer state `ℓ`,
plus other changes `C`.

$$\forall \ell, C:\ \operatorname{crFade}(\ell, C) = \operatorname{jsWrite}\big(1,\ (\mathrm{panel}, \mathrm{fadeProp}, \ell) :: C\big)$$

The frame the fade writes. -/
def crFade (ℓ : LayerState) (cs : List (Change CrProp)) : FrameIn CrProp :=
  jsWrite 1 (⟨panel, fadeProp, ℓ⟩ :: cs)

open Fw.Engine.Chromium in
/-- The Chromium enter frame without other changes runs no layout, so `cr_toggle_not_le` applies to it.

$$\operatorname{frameWork}_{\mathrm{chromium}}(\operatorname{crFade}(\mathrm{layer}, [\,])).\mathrm{passes}(\mathrm{layout}) = 0$$

A plain fade write does not lay out. -/
theorem cr_enter_layout_zero : (frameWork chromium (crFade .layer [])).passes .layout = 0 := by decide

open Fw.Engine.WebKit in
/-- **The original's WebKit toggle frame** (enter or leave): opacity crosses 1, and the filter value changes.

$$\forall \ell:\ \operatorname{wkEdge}_o(\ell) = \operatorname{jsFrame}[(\mathrm{panel}, \mathrm{opacityCross1}, \ell), (\mathrm{panel}, \mathrm{filter}, \ell)]$$

`blur(0)` ↔ `blur(x)` with the opacity flip. -/
def wkEdgeO (ℓ : LayerState) : FrameIn WkProp := jsFrame [⟨panel, .opacityCross1, ℓ⟩, ⟨panel, .filter, ℓ⟩]

open Fw.Engine.WebKit in
/-- **The variant's WebKit toggle frame**: opacity crosses 1, and the filter appears or disappears.

$$\forall \ell:\ \operatorname{wkEdge}_v(\ell) = \operatorname{jsFrame}[(\mathrm{panel}, \mathrm{opacityCross1}, \ell), (\mathrm{panel}, \mathrm{filterToggle}, \ell)]$$

`none` ↔ `blur(x)` with the opacity flip. -/
def wkEdgeV (ℓ : LayerState) : FrameIn WkProp := jsFrame [⟨panel, .opacityCross1, ℓ⟩, ⟨panel, .filterToggle, ℓ⟩]

open Fw.Engine.WebKit in
/-- **WebKit toggle frame, layout units**: the flip is a layout change (`filterToggle` has raw level Layout,
`WC/style/StyleDifference.cpp:217`), and so is the original's `blur(0)` ↔ `blur(x)` value change, because it changes
the filter outsets (`WC/style/StyleDifference.cpp:68-83`@862f17d, CONFIRMED; MEASURED by the engine-premises lane).
Both arms lay out 2 changes.

Changed since CI run 39088367495: the original's filter change was modelled as no layout (1 unit against 2).

$$\forall \ell:\ \operatorname{frameWork}_{\mathrm{webkit}}(\operatorname{wkEdge}_v(\ell)).\mathrm{units}(\mathrm{layout}) = 2 \land \operatorname{frameWork}_{\mathrm{webkit}}(\operatorname{wkEdge}_o(\ell)).\mathrm{units}(\mathrm{layout}) = 2$$

Both toggle frames lay out the panel twice. -/
theorem wk_toggle_layout_units (ℓ : LayerState) :
    (frameWork webkit (wkEdgeV ℓ)).units .layout = 2 ∧ (frameWork webkit (wkEdgeO ℓ)).units .layout = 2 := by
  cases ℓ <;> decide

open Fw.Engine.WebKit in
/-- **WebKit toggle frame, passes equal**: the opacity flip already lays out in both arms.

$$\forall \ell,\ \forall s \in \mathrm{Stage}:\ \operatorname{frameWork}_{\mathrm{webkit}}(\operatorname{wkEdge}_v(\ell)).\mathrm{passes}(s) = \operatorname{frameWork}_{\mathrm{webkit}}(\operatorname{wkEdge}_o(\ell)).\mathrm{passes}(s)$$

Same stages run in both arms. -/
theorem wk_toggle_passes (ℓ : LayerState) (s : Stage) :
    (frameWork webkit (wkEdgeV ℓ)).passes s = (frameWork webkit (wkEdgeO ℓ)).passes s := by
  cases ℓ <;> cases s <;> decide

open Fw.Engine.WebKit in
/-- **WebKit toggle frame: equal work.** The variant's toggle frame and the original's have the same work in both
directions of `≼`: each change in either arm is a Layout-level difference.

Changed since CI run 39088367495: this replaces `wk_toggle_not_le` (the variant's frame was not below the
original's, by one layout unit), which the corrected filter rule refutes.

$$\forall \ell:\ \operatorname{frameWork}_{\mathrm{webkit}}(\operatorname{wkEdge}_v(\ell)) \preceq \operatorname{frameWork}_{\mathrm{webkit}}(\operatorname{wkEdge}_o(\ell)) \land \operatorname{frameWork}_{\mathrm{webkit}}(\operatorname{wkEdge}_o(\ell)) \preceq \operatorname{frameWork}_{\mathrm{webkit}}(\operatorname{wkEdge}_v(\ell))$$

On WebKit the `none` ↔ `blur` flip costs nothing over the original's toggle. -/
theorem wk_toggle_eqv (ℓ : LayerState) :
    (frameWork webkit (wkEdgeV ℓ)).eqv (frameWork webkit (wkEdgeO ℓ)) := by
  cases ℓ <;> exact ⟨frame_le_union webkit (by decide), frame_le_union webkit (by decide)⟩

/-! ## WebKit over a whole run that crosses rest and fade (`wk_cross_claim`) -/

/-- **One frame of a WebKit run** of the rest variant: a rest frame (`φ = 1`), a toggle frame (opacity crosses 1 and
the filter flips, layer state `ℓ`), or a fade frame with work `w`. A fade frame is the same in both arms, because the
variant writes the original's filter whenever `φ < 1` (`filterV_fade`).

$$\mathrm{WkCross} = \mathrm{rest}(\mathrm{RestIn}(\mathrm{WkProp})) \mid \mathrm{edge}(\mathrm{LayerState}) \mid \mathrm{fade}(\mathrm{Work})$$

The three kinds of frame in a swipe that leaves rest and comes back. -/
inductive WkCross where
  | rest (x : RestIn WebKit.WkProp)
  | edge (ℓ : LayerState)
  | fade (w : Work)

open Fw.Engine.WebKit in
/-- **The original's WebKit work** of one frame: `blur(0)` at rest, the `blur(0)` ↔ `blur(x)` toggle, the fade
frame's work.

$$\forall x, \ell, w:\ W_o(\mathrm{rest}(x)) = W_{\mathrm{wk}}(F_o(1), x),\quad W_o(\mathrm{edge}(\ell)) = \operatorname{frameWork}_{\mathrm{webkit}}(\operatorname{wkEdge}_o(\ell)),\quad W_o(\mathrm{fade}(w)) = w$$

What each frame of the run costs the original. -/
def wkCrossO : WkCross → Work
  | .rest x => wkRestW (filterO 1) x
  | .edge ℓ => frameWork webkit (wkEdgeO ℓ)
  | .fade w => w

open Fw.Engine.WebKit in
/-- **The variant's WebKit work** of one frame: `none` at rest, the `none` ↔ `blur(x)` toggle, the fade frame's work.

$$\forall x, \ell, w:\ W_v(\mathrm{rest}(x)) = W_{\mathrm{wk}}(F_v(1), x),\quad W_v(\mathrm{edge}(\ell)) = \operatorname{frameWork}_{\mathrm{webkit}}(\operatorname{wkEdge}_v(\ell)),\quad W_v(\mathrm{fade}(w)) = w$$

What each frame of the run costs the variant. -/
def wkCrossV : WkCross → Work
  | .rest x => wkRestW (filterV 1) x
  | .edge ℓ => frameWork webkit (wkEdgeV ℓ)
  | .fade w => w

/-- `φ = 1` is rest: the progress `0` gives the full fade.

$$\operatorname{fade}(0) = 1$$

Rest frames use the filters at `φ = 1`. -/
theorem fade_zero : fade 0 = 1 := by unfold fade; grind

/-- **WebKit, every frame of the run**: the variant is at most the original, frame by frame (rest by `wk_rest_le`,
toggle by `wk_toggle_eqv`, fade equal).

$$\forall c \in \mathrm{WkCross}:\ W_v(c) \preceq W_o(c)$$

No frame of a rest-fade-rest swipe costs WebKit more. -/
theorem wk_cross_le (c : WkCross) : (wkCrossV c).le (wkCrossO c) := by
  cases c with
  | rest x => have h := wk_rest_le (r := 0) (by decide) x; rw [fade_zero] at h; exact h
  | edge ℓ => exact (wk_toggle_eqv ℓ).1
  | fade w => exact Work.le_refl w

/-- **WebKit resident state over the run**: whatever fade value `φ` the variant's resident state is taken at, and
`φ'` the original's, the variant's is at most the original's (the original's filter is never `none`).

$$\forall \varphi, \varphi' \in \mathbb{Q},\ \forall d \in \mathbb{B},\ \forall \mathrm{res} \in \mathrm{Resident},\ \forall k \in \mathbb{N}:\ \operatorname{res}_{\mathrm{wk}}(F_v(\varphi), d, \mathrm{res}, k) \preceq \operatorname{res}_{\mathrm{wk}}(F_o(\varphi'), d, \mathrm{res}, k)$$

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

$$\forall X \in \mathrm{WkCross}^{*}:\ \big(\exists x:\ \mathrm{rest}(x) \in X \land x.\mathrm{drawSurface}\big) \Rightarrow \forall \varphi, \varphi' \in \mathbb{Q},\ \forall d \in \mathbb{B},\ \forall \mathrm{res} \in \mathrm{Resident},\ \forall k \in \mathbb{N}:\ \operatorname{claim}\big(\operatorname{screen}(\operatorname{toRun}(\operatorname{map}(W_o, X)), \operatorname{toRun}(\operatorname{map}(W_v, X))), \operatorname{res}_{\mathrm{wk}}(F_v(\varphi), d, \mathrm{res}, k), \operatorname{res}_{\mathrm{wk}}(F_o(\varphi'), d, \mathrm{res}, k)\big) = \mathrm{dominates}$$

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

$$\forall E,\ \forall L:\ \operatorname{cover}_E(L, L) = \mathrm{true}$$

Every change covers itself. -/
theorem coverB_self {P M : Type} (E : Engine P M) : ∀ cs : List (Change P), coverB E cs cs = true
  | [] => rfl
  | c :: cs => by simp [coverB, coverB_self E cs]

open Fw.Engine.Chromium in
/-- **Chromium fade frame, per frame `≤`**: the fade write re-rasters (`raster`) on every layer state, so the own
layer adds no work in a fade frame (the frames are in fact equal, `cr_fade_eq`).

Changed since CI run 39088367495: on its own layer the blur write was modelled as a property-tree update (`ppFull`,
below `raster`); the engine-premises lane MEASURED a raster for a blur value change on an own layer.

$$\forall \ell_o \ne \mathrm{own},\ \forall C:\ \operatorname{frameWork}_{\mathrm{chromium}}(\operatorname{crFade}(\mathrm{own}, C)) \preceq \operatorname{frameWork}_{\mathrm{chromium}}(\operatorname{crFade}(\ell_o, C))$$

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

$$\forall \ell:\ \operatorname{chromium.stagesOf}(\mathrm{panel}, \mathrm{fadeProp}, \ell) = \operatorname{stages}(\mathrm{raster})$$

The own layer does not take the blur off the raster path. -/
theorem cr_fade_stages (ℓ : LayerState) :
    chromium.stagesOf ⟨panel, fadeProp, ℓ⟩ = CrLevel.raster.stages := by
  cases ℓ <;> decide

open Fw.Engine.Chromium in
/-- **Chromium fade frames are equal** in both arms: the fade frame on the own layer has the same work as on any
other layer state.

$$\forall \ell_o,\ \forall C:\ \operatorname{frameWork}_{\mathrm{chromium}}(\operatorname{crFade}(\mathrm{own}, C)) = \operatorname{frameWork}_{\mathrm{chromium}}(\operatorname{crFade}(\ell_o, C))$$

An own layer changes no counted work in a Chromium fade frame. -/
theorem cr_fade_eq (ℓo : LayerState) (cs : List (Change CrProp)) :
    frameWork chromium (crFade .own cs) = frameWork chromium (crFade ℓo cs) := by
  cases ℓo <;> rfl

/-- **Resident state with or without the panel's own layer**: one more composited layer and its backing `kpx`.

$$\forall b, \rho, k:\ \operatorname{res}(b, \rho, k) = \begin{cases} (\rho.\mathrm{layers} + 1,\ \rho.\mathrm{backingKpx} + k) & b \\ \rho & \neg b \end{cases}$$

The cost of the own layer while it exists. -/
def ownResident (own : Bool) (res : Resident) (kpx : Nat) : Resident :=
  if own then ⟨res.layers + 1, res.backingKpx + kpx⟩ else res

/-- **The layer increase**: the own layer adds exactly one resident layer.

$$\forall \rho, k:\ \operatorname{res}(\mathrm{true}, \rho, k).\mathrm{layers} = \operatorname{res}(\mathrm{false}, \rho, k).\mathrm{layers} + 1$$

Layers +1 during the fade. -/
theorem fade_layers_up (res : Resident) (kpx : Nat) :
    (ownResident true res kpx).layers = (ownResident false res kpx).layers + 1 := rfl

open Fw.Engine.Chromium in
/-- **(work) during the fade, Chromium: no claim.** Over any run of fade frames the two arms have equal counted work
(`cr_fade_eq`), so the claim is "noClaim" whatever the resident states (`resident_only_noClaim`); the own layer only
adds a resident layer (`fade_layers_up`).

Changed since CI run 39088367495: this replaces `cr_fade_trade` (claim "trade": raster down, layers up), which rested
on the refuted `ppFull` rule for a blur on an own layer. The sign of the Chromium half changed from trade to no-win.

$$\forall \ell_o,\ \forall \mathcal{C},\ \forall \rho, k:\ \operatorname{claim}\Big(\operatorname{screen}\big(\operatorname{toRun}[\operatorname{frameWork}_{\mathrm{chromium}}(\operatorname{crFade}(\ell_o, C))]_{C \in \mathcal{C}}, \operatorname{toRun}[\operatorname{frameWork}_{\mathrm{chromium}}(\operatorname{crFade}(\mathrm{own}, C))]_{C \in \mathcal{C}}\big), \operatorname{res}(\mathrm{true}, \rho, k), \operatorname{res}(\mathrm{false}, \rho, k)\Big) = \mathrm{noClaim}$$

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

$$\forall C:\ \operatorname{wkFade}_o(C) = \operatorname{jsFrame}\big((\mathrm{panel}, \mathrm{filter}, \mathrm{layer}) :: (\mathrm{panel}, \mathrm{opacity}, \mathrm{layer}) :: C\big)$$

One fade step, painted. -/
def wkFadeO (cs : List (Change WkProp)) : FrameIn WkProp :=
  jsFrame (⟨panel, .filter, .layer⟩ :: ⟨panel, .opacity, .layer⟩ :: cs)

open Fw.Engine.WebKit in
/-- **The variant's WebKit fade frame** on the own layer: the composited filter and the opacity change.

$$\forall C:\ \operatorname{wkFade}_v(C) = \operatorname{jsFrame}\big((\mathrm{panel}, \mathrm{filter}, \mathrm{own}) :: (\mathrm{panel}, \mathrm{opacity}, \mathrm{own}) :: C\big)$$

One fade step, composited. -/
def wkFadeV (cs : List (Change WkProp)) : FrameIn WkProp :=
  jsFrame (⟨panel, .filter, .own⟩ :: ⟨panel, .opacity, .own⟩ :: cs)

open Fw.Engine.WebKit in
/-- **WebKit fade: the paint drop.** The opacity change leaves `paint` on the own layer; the blur change paints in
both arms (it is a Layout-level change).

Changed since CI run 39088367495: the drop was 2 units (the filter change also left paint); the corrected filter
rule makes the blur change Layout on every layer state.

$$\forall C:\ \operatorname{frameWork}_{\mathrm{webkit}}(\operatorname{wkFade}_v(C)).\mathrm{units}(\mathrm{paint}) + 1 = \operatorname{frameWork}_{\mathrm{webkit}}(\operatorname{wkFade}_o(C)).\mathrm{units}(\mathrm{paint})$$

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

$$\forall C:\ \operatorname{frameWork}_{\mathrm{webkit}}(\operatorname{wkFade}_v(C)).\mathrm{units}(\mathrm{props}) + 1 = \operatorname{frameWork}_{\mathrm{webkit}}(\operatorname{wkFade}_o(C)).\mathrm{units}(\mathrm{props})$$

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

$$\forall C:\ \operatorname{frameWork}_{\mathrm{webkit}}(\operatorname{wkFade}_v(C)) \preceq \operatorname{frameWork}_{\mathrm{webkit}}(\operatorname{wkFade}_o(C))$$

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

$$\forall \mathcal{C} \ne [\,],\ \forall \rho, k:\ \operatorname{claim}\Big(\operatorname{screen}\big(\operatorname{toRun}[\operatorname{frameWork}_{\mathrm{webkit}}(\operatorname{wkFade}_o(C))]_{C \in \mathcal{C}}, \operatorname{toRun}[\operatorname{frameWork}_{\mathrm{webkit}}(\operatorname{wkFade}_v(C))]_{C \in \mathcal{C}}\big), \operatorname{res}(\mathrm{true}, \rho, k), \operatorname{res}(\mathrm{false}, \rho, k)\Big) = \mathrm{trade}$$

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

$$\mathrm{restCr} = (\operatorname{jsWrite}(1, [\,]),\ \mathrm{false},\ \mathrm{false},\ \mathrm{true})$$

A scroll frame while the panel rests. -/
def restCr : RestIn Chromium.CrProp := ⟨Chromium.jsWrite 1 [], false, false, true⟩

/-- The WebKit rest frame, as `restCr`.

$$\mathrm{restWk} = (\operatorname{jsFrame}([\,]),\ \mathrm{false},\ \mathrm{false},\ \mathrm{true})$$

A scroll frame while the panel rests. -/
def restWk : RestIn WebKit.WkProp := ⟨WebKit.jsFrame [], false, false, true⟩

open Fw.Engine.Chromium in
/-- The Chromium fade frame, identical in both arms of the golden variant: the `--morph-fade` write on the
non-composited panel plus the compositor draw of its effect.

$$\mathrm{fadeCr} = \operatorname{bump}(\operatorname{frameWork}_{\mathrm{chromium}}(\operatorname{crFade}(\mathrm{layer}, [\,])), [\mathrm{comp}])$$

One fade step in Chromium. -/
def fadeCr : Work := bump (frameWork chromium (crFade .layer [])) [.comp]

/-- **The Chromium original arm**: rest frames carry the `blur(0)` effect; enter, fade and leave are fade frames.

$$\mathrm{crO} = [r_o, r_o, \mathrm{fadeCr}, \mathrm{fadeCr}, \mathrm{fadeCr}, \mathrm{fadeCr}, r_o, r_o],\quad r_o = W_{\mathrm{cr}}(F_o(\operatorname{fade}(0)), \mathrm{restCr})$$

What the original's swipe costs in Chromium. -/
def crO : List Work :=
  let r := crRestW (filterO (fade 0)) restCr
  [r, r, fadeCr, fadeCr, fadeCr, fadeCr, r, r]

/-- **The Chromium variant arm**: rest frames have no effect; the enter and leave frames add the stacking-context
flip (full layout).

$$\mathrm{crV} = [r_v, r_v, e, \mathrm{fadeCr}, \mathrm{fadeCr}, e, r_v, r_v],\quad r_v = W_{\mathrm{cr}}(F_v(\operatorname{fade}(0)), \mathrm{restCr}),\ e = \operatorname{bump}(\mathrm{fadeCr}, \operatorname{stages}(\mathrm{layoutFull}))$$

What the variant's swipe costs in Chromium. -/
def crV : List Work :=
  let r := crRestW (filterV (fade 0)) restCr
  let e := bump fadeCr Chromium.CrLevel.layoutFull.stages
  [r, r, e, fadeCr, fadeCr, e, r, r]

open Fw.Engine.WebKit in
/-- The WebKit fade frame, identical in both arms: filter and opacity changes on the indirectly composited panel
plus the compositor draw.

$$\mathrm{fadeWk} = \operatorname{bump}(\operatorname{frameWork}_{\mathrm{webkit}}(\operatorname{jsFrame}[(\mathrm{panel}, \mathrm{filter}, \mathrm{own}), (\mathrm{panel}, \mathrm{opacity}, \mathrm{own})]), [\mathrm{comp}])$$

One fade step in WebKit. -/
def fadeWk : Work := bump (frameWork webkit (jsFrame [⟨panel, .filter, .own⟩, ⟨panel, .opacity, .own⟩])) [.comp]

open Fw.Engine.WebKit in
/-- **The WebKit original arm**: the toggle frames change the filter value (`filter`).

$$\mathrm{wkO} = [r_o, r_o, e_o, \mathrm{fadeWk}, \mathrm{fadeWk}, e_o, r_o, r_o],\quad r_o = W_{\mathrm{wk}}(F_o(\operatorname{fade}(0)), \mathrm{restWk}),\ e_o = \operatorname{bump}(\operatorname{frameWork}_{\mathrm{webkit}}(\operatorname{wkEdge}_o(\mathrm{own})), [\mathrm{comp}])$$

What the original's swipe costs in WebKit. -/
def wkO : List Work :=
  let r := wkRestW (filterO (fade 0)) restWk
  let e := bump (frameWork webkit (wkEdgeO .own)) [.comp]
  [r, r, e, fadeWk, fadeWk, e, r, r]

open Fw.Engine.WebKit in
/-- **The WebKit variant arm**: the toggle frames add or remove the filter (`filterToggle`).

$$\mathrm{wkV} = [r_v, r_v, e_v, \mathrm{fadeWk}, \mathrm{fadeWk}, e_v, r_v, r_v],\quad r_v = W_{\mathrm{wk}}(F_v(\operatorname{fade}(0)), \mathrm{restWk}),\ e_v = \operatorname{bump}(\operatorname{frameWork}_{\mathrm{webkit}}(\operatorname{wkEdge}_v(\mathrm{own})), [\mathrm{comp}])$$

What the variant's swipe costs in WebKit. -/
def wkV : List Work :=
  let r := wkRestW (filterV (fade 0)) restWk
  let e := bump (frameWork webkit (wkEdgeV .own)) [.comp]
  [r, r, e, fadeWk, fadeWk, e, r, r]

/-- One count type: its name, the stage it counts, whether it counts units (else passes), and whether its class is
frame-exact (else judged by totals).

$$\mathrm{CountType} = \mathrm{String} \times \mathrm{Stage} \times \mathbb{B} \times \mathbb{B}$$

How a measured counter maps to the model. -/
structure CountType where
  name : String
  stage : Stage
  units : Bool
  exact : Bool

/-- The JSON name of a stage.

$$\operatorname{stageName}(s) = \text{the constructor name of } s$$

As in the engine golden files. -/
def stageName : Stage → String
  | .script => "script" | .style => "style" | .layout => "layout" | .props => "props"
  | .paint => "paint" | .raster => "raster" | .commit => "commit" | .comp => "comp"

#guard stageName .layout == "layout" && stageName .comp == "comp"

/-- The per-frame series of one count type over an arm.

$$\forall W, t:\ \operatorname{series}(W, t) = [\, t.\mathrm{units} \mathbin{?} \operatorname{units}(w, t.\mathrm{stage}) : \operatorname{passes}(w, t.\mathrm{stage}) \,]_{w \in W}$$

What the counter would read frame by frame. -/
def series (ws : List Work) (t : CountType) : List Nat :=
  ws.map fun w => if t.units then w.units t.stage else w.passes t.stage

#guard series crV ⟨"x", .layout, false, false⟩ == [0, 0, 1, 0, 0, 1, 0, 0]
#guard series crO ⟨"x", .layout, false, false⟩ == [0, 0, 0, 0, 0, 0, 0, 0]

/-- **The prediction for one row**, first match: every variant frame zero gives `=0`; a frame-exact class gives `=o`
for an equal series, `<o` for a pointwise-below series of the same length, else `any`; a totals class gives `=o`
for equal sums, `≤o` for a smaller sum, else `any`.

$$\forall x \in \mathbb{B},\ \forall v, o \in \mathbb{N}^{*}:\ \operatorname{predict}(x, v, o) = \begin{cases} \texttt{=0} & \forall i < |v|,\ v_i = 0 \quad (\text{also } v = [\,]) \\ \texttt{=o} & \neg(\forall i < |v|,\ v_i = 0) \land x \land v = o \\ \texttt{<o} & \neg(\forall i < |v|,\ v_i = 0) \land x \land v \ne o \land |v| = |o| \land \forall i < |v|,\ v_i \le o_i \\ \texttt{any} & \neg(\forall i < |v|,\ v_i = 0) \land x \land \text{neither of the two above} \\ \texttt{=o} & \neg(\forall i < |v|,\ v_i = 0) \land \neg x \land \textstyle\sum v = \sum o \\ \texttt{≤o} & \neg(\forall i < |v|,\ v_i = 0) \land \neg x \land \textstyle\sum v < \sum o \\ \texttt{any} & \neg(\forall i < |v|,\ v_i = 0) \land \neg x \land \textstyle\sum v > \sum o \end{cases}$$

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

$$\begin{aligned} \mathrm{crTypes} = [\ &(\texttt{trace.FunctionCall}, \mathrm{script}, \top, \top),\ (\texttt{trace.UpdateLayoutTree}, \mathrm{style}, \bot, \top), \\ &(\texttt{trace.Layout}, \mathrm{layout}, \bot, \bot),\ (\texttt{trace.Layout.dirtyObjects}, \mathrm{layout}, \top, \bot), \\ &(\texttt{metric.LayoutCount}, \mathrm{layout}, \bot, \bot),\ (\texttt{trace.PrePaint}, \mathrm{props}, \bot, \bot), \\ &(\texttt{raster.invalidationAreaPx}, \mathrm{paint}, \top, \bot),\ (\texttt{trace.cc.Commit}, \mathrm{commit}, \bot, \top)\ ] \end{aligned}$$

Which counter reads which stage. -/
def crTypes : List CountType :=
  [⟨"trace.FunctionCall", .script, true, true⟩, ⟨"trace.UpdateLayoutTree", .style, false, true⟩,
   ⟨"trace.Layout", .layout, false, false⟩, ⟨"trace.Layout.dirtyObjects", .layout, true, false⟩,
   ⟨"metric.LayoutCount", .layout, false, false⟩, ⟨"trace.PrePaint", .props, false, false⟩,
   ⟨"raster.invalidationAreaPx", .paint, true, false⟩, ⟨"trace.cc.Commit", .commit, false, true⟩]

/-- The WebKit count types (no frozen classes yet; judged by totals), as in `morph-mount.jsonl`. Each entry is (name, stage, units, exact).

$$\mathrm{wkTypes} = [(\texttt{RecalculateStyles}, \mathrm{style}, \bot, \bot),\ (\texttt{Layout}, \mathrm{layout}, \bot, \bot),\ (\texttt{Paint}, \mathrm{paint}, \bot, \bot),\ (\texttt{Composite}, \mathrm{commit}, \bot, \bot)]$$

Which counter reads which stage. -/
def wkTypes : List CountType :=
  [⟨"RecalculateStyles", .style, false, false⟩, ⟨"Layout", .layout, false, false⟩,
   ⟨"Paint", .paint, false, false⟩, ⟨"Composite", .commit, false, false⟩]

/-- One JSON row, keys sorted.

$$\operatorname{row}(e, sc, t, v, o) = \{\mathrm{base} = \text{rewrite}, \mathrm{countType} = t.\mathrm{name}, \mathrm{engine} = e, \mathrm{prediction} = \operatorname{predict}(t.\mathrm{exact}, \operatorname{series}(v, t), \operatorname{series}(o, t)), \mathrm{scenario} = sc, \mathrm{stage} = \operatorname{stageName}(t.\mathrm{stage}), \mathrm{variant} = \text{rewrite+?fw=morph.panel:rest}\}$$

The variant flag is `?fw=morph.panel:rest`; the base is the faithful rewrite. -/
def row (engine scenario : String) (t : CountType) (vs os : List Work) : String :=
  "{\"base\":\"rewrite\",\"countType\":\"" ++ t.name ++ "\",\"engine\":\"" ++ engine ++ "\",\"prediction\":\"" ++
    predict t.exact (series vs t) (series os t) ++ "\",\"scenario\":\"" ++ scenario ++ "\",\"stage\":\"" ++
    stageName t.stage ++ "\",\"variant\":\"rewrite+?fw=morph.panel:rest\"}"

/-- All golden rows: Chromium on `swipe-v1` and `swipe-touch-v1`, WebKit on `swipe-v1`.

$$\mathrm{goldenLines} = [\,\operatorname{row}(\texttt{chromium}, sc, t, \mathrm{crV}, \mathrm{crO}) \mid sc \in [\texttt{swipe-v1}, \texttt{swipe-touch-v1}],\ t \in \mathrm{crTypes}\,] \mathbin{+\!\!+} [\,\operatorname{row}(\texttt{webkit}, \texttt{swipe-v1}, t, \mathrm{wkV}, \mathrm{wkO}) \mid t \in \mathrm{wkTypes}\,]$$

The list comprehension runs $sc$ outer and $t$ inner, so there are $2 \cdot 8 + 4 = 20$ lines.
The file `packages/contracts/golden/engine/morph-panel.jsonl`, line by line. -/
def goldenLines : List String :=
  (["swipe-v1", "swipe-touch-v1"].flatMap fun sc => crTypes.map fun t => row "chromium" sc t crV crO) ++
    wkTypes.map fun t => row "webkit" "swipe-v1" t wkV wkO

/-- The golden file text: one row per line, trailing newline.

$$\mathrm{goldenText} = \operatorname{concat}[\, \ell \mathbin{+\!\!+} \text{"\textbackslash n"} \,]_{\ell \in \mathrm{goldenLines}}$$

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

$$\forall F, x, e:\ W^{e}_{\mathrm{cr}}(F, x) = \begin{cases} \operatorname{bump}(\operatorname{frameWork}^{e}_{\mathrm{chromium}}(x.f), S_{\mathrm{cr}}(x)) & F \ne [\,] \\ \operatorname{frameWork}^{e}_{\mathrm{chromium}}(x.f) & F = [\,] \end{cases}$$

The rest frame's cost with the frame-end pass counted. -/
def crRestWE (F : List FilterOp) (x : RestIn CrProp) (e : Stage → Bool) : Work :=
  if groups F then bump (frameWorkE chromium x.f e) (crEffectStages x) else frameWorkE chromium x.f e

open Fw.Engine.WebKit in
/-- WebKit work of a rest frame under `frameWorkE`, with end flags `e`.

$$\forall F, x, e:\ W^{e}_{\mathrm{wk}}(F, x) = \begin{cases} \operatorname{bump}(\operatorname{frameWork}^{e}_{\mathrm{webkit}}(x.f), S_{\mathrm{wk}}(x)) & F \ne [\,] \\ \operatorname{frameWork}^{e}_{\mathrm{webkit}}(x.f) & F = [\,] \end{cases}$$

The rest frame's cost with the frame-end pass counted. -/
def wkRestWE (F : List FilterOp) (x : RestIn WkProp) (e : Stage → Bool) : Work :=
  if groups F then bump (frameWorkE webkit x.f e) (wkEffectStages x) else frameWorkE webkit x.f e

/-- **Chromium rest frame under `frameWorkE`: `≤`.**

$$\forall r \in \mathbb{Q},\ \forall x,\ \forall e:\ r \le 0 \Rightarrow W^{e}_{\mathrm{cr}}(F_v(\operatorname{fade}(r)), x) \preceq W^{e}_{\mathrm{cr}}(F_o(\operatorname{fade}(r)), x)$$

Dropping `blur(0)` never adds work, end pass or not. -/
theorem cr_rest_leE {r : Rat} (hr : r ≤ 0) (x : RestIn Chromium.CrProp) (e : Stage → Bool) :
    (crRestWE (filterV (fade r)) x e).le (crRestWE (filterO (fade r)) x e) := by
  unfold crRestWE; rw [filterV_rest hr, filterO_rest hr]; exact le_bump _ _

/-- **Chromium rest frame under `frameWorkE`: strict** when the frame has a raster, property or surface step.

$$\forall r, x, e:\ r \le 0 \land (x.\mathrm{rasterUnder} \lor x.\mathrm{propsPanel} \lor x.\mathrm{drawSurface}) \Rightarrow W^{e}_{\mathrm{cr}}(F_v(\operatorname{fade}(r)), x) \prec W^{e}_{\mathrm{cr}}(F_o(\operatorname{fade}(r)), x)$$

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

$$\forall r \in \mathbb{Q},\ \forall x,\ \forall e:\ r \le 0 \Rightarrow W^{e}_{\mathrm{wk}}(F_v(\operatorname{fade}(r)), x) \preceq W^{e}_{\mathrm{wk}}(F_o(\operatorname{fade}(r)), x)$$

The same in Safari. -/
theorem wk_rest_leE {r : Rat} (hr : r ≤ 0) (x : RestIn WebKit.WkProp) (e : Stage → Bool) :
    (wkRestWE (filterV (fade r)) x e).le (wkRestWE (filterO (fade r)) x e) := by
  unfold wkRestWE; rw [filterV_rest hr, filterO_rest hr]; exact le_bump _ _

end EndPass

end Fw.Parts.MorphPanelOpt
