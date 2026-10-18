import Fw.Guidance.Basic
/-!
# Guidance rules on layout stability: reserved media space, stable scrollbar gutter

Rules `perf.cls.reserve-media-space` and `layout.scrollbar-gutter`, on the work side only: the models have no layout
shift score. `perf.css.contain-intrinsic-size` and `fonts.size-adjust-fallback` are out of model (no theorem here).
-/
namespace Fw.Guidance.Stability

open Fw.Engine

/-- **A reserved box turns the decode into a paint (Chromium).** On any layer state, a paint-only change of a box
(the image content) is strictly less work than a height change of the same box.

$$\forall m \in \mathrm{CrMode},\ \forall e, e' \in \mathbb{N},\ \forall l \in \mathrm{LayerState}:\ \operatorname{frameWork}_E\big(\operatorname{changesOnly}([(e, \mathrm{css}(\mathrm{bgImage}), l)])\big) \prec \operatorname{frameWork}_E\big(\operatorname{changesOnly}([(e', \mathrm{css}(\mathrm{height}), l)])\big)\quad\text{where } E = \operatorname{chromiumAt}(m)$$

The image decode is modelled as a background-image change; without a reserved box it is also a height change. -/
theorem cr_reserve_lt (m : Chromium.CrMode) (e e' : Nat) (l : LayerState) :
    (frameWork (Chromium.chromiumAt m) (changesOnly [⟨e, .css .backgroundImage, l⟩])).lt
      (frameWork (Chromium.chromiumAt m) (changesOnly [⟨e', .css .height, l⟩])) := by
  refine lt_of_le_units .layout (frame_le_of_cover (Chromium.chromiumAt m) [⟨e', .css .height, l⟩] []
    (by simp [changesOnly]) ?_ (Nat.le_refl _) (Nat.le_refl _) (Nat.le_refl _) (Nat.le_refl _) (Nat.le_refl _)) ?_
  · cases l <;> rfl
  · show stageUnits (Chromium.chromiumAt m) _ .layout < stageUnits (Chromium.chromiumAt m) _ .layout
    obtain ⟨t, b⟩ := m
    cases t <;> cases b <;> cases l <;> exact Nat.zero_lt_one

/-- **A reserved box turns the decode into a paint (WebKit).** On any layer state, a background change of a box is
strictly less work than a size change of the same box.

$$\forall m \in \mathrm{WkMode},\ \forall e, e' \in \mathbb{N},\ \forall \ell \in \mathrm{LayerState}:\ \operatorname{frameWork}_E\big(\operatorname{changesOnly}([(e, \mathrm{background}, \ell)])\big) \prec \operatorname{frameWork}_E\big(\operatorname{changesOnly}([(e', \mathrm{size}, \ell)])\big)\quad\text{where } E = \operatorname{webkitAt}(m)$$

The image decode is modelled as a repaint; without a reserved box it is also a size change. -/
theorem wk_reserve_lt (m : WebKit.WkMode) (e e' : Nat) (ℓ : LayerState) :
    (frameWork (WebKit.webkitAt m) (changesOnly [⟨e, .background, ℓ⟩])).lt
      (frameWork (WebKit.webkitAt m) (changesOnly [⟨e', .size, ℓ⟩])) := by
  refine lt_of_le_units .layout (frame_le_of_cover (WebKit.webkitAt m) [⟨e', .size, ℓ⟩] []
    (by simp [changesOnly]) ?_ (Nat.le_refl _) (Nat.le_refl _) (Nat.le_refl _) (Nat.le_refl _) (Nat.le_refl _)) ?_
  · cases ℓ <;> rfl
  · show stageUnits (WebKit.webkitAt m) _ .layout < stageUnits (WebKit.webkitAt m) _ .layout
    cases ℓ <;> exact Nat.zero_lt_one

/-- **A stable gutter saves the width change (Chromium).** A frame is strictly less work than the same frame plus a
width change of the content box, on any layer state.

$$\forall m \in \mathrm{CrMode},\ \forall f \in \mathrm{FrameIn}(\mathrm{CrProp}),\ \forall e \in \mathbb{N},\ \forall l \in \mathrm{LayerState}:\ \operatorname{frameWork}_E(f) \prec \operatorname{frameWork}_E\big(\operatorname{join}(f, \operatorname{changesOnly}([(e, \mathrm{css}(\mathrm{width}), l)]))\big)\quad\text{where } E = \operatorname{chromiumAt}(m)$$

A scrollbar that appears without a reserved gutter is modelled as a width change of the content. -/
theorem cr_gutter_lt (m : Chromium.CrMode) (f : FrameIn Chromium.CrProp) (e : Nat) (l : LayerState) :
    (frameWork (Chromium.chromiumAt m) f).lt
      (frameWork (Chromium.chromiumAt m) (join f (changesOnly [⟨e, .css .width, l⟩]))) := by
  refine frame_lt_join_change _ f _ ⟨e, .css .width, l⟩ (by simp [changesOnly]) .layout ?_
  show Stage.layout ∈ Chromium.crStagesOf ⟨0, .css .width, l⟩
  cases l <;> decide

/-- **A stable gutter saves the width change (WebKit).** A frame is strictly less work than the same frame plus a size
change of the content box, on any layer state.

$$\forall m \in \mathrm{WkMode},\ \forall f \in \mathrm{FrameIn}(\mathrm{WkProp}),\ \forall e \in \mathbb{N},\ \forall \ell \in \mathrm{LayerState}:\ \operatorname{frameWork}_E(f) \prec \operatorname{frameWork}_E\big(\operatorname{join}(f, \operatorname{changesOnly}([(e, \mathrm{size}, \ell)]))\big)\quad\text{where } E = \operatorname{webkitAt}(m)$$

A scrollbar that appears without a reserved gutter is modelled as a size change of the content. -/
theorem wk_gutter_lt (m : WebKit.WkMode) (f : FrameIn WebKit.WkProp) (e : Nat) (ℓ : LayerState) :
    (frameWork (WebKit.webkitAt m) f).lt
      (frameWork (WebKit.webkitAt m) (join f (changesOnly [⟨e, .size, ℓ⟩]))) := by
  refine frame_lt_join_change _ f _ ⟨e, .size, ℓ⟩ (by simp [changesOnly]) .layout ?_
  show Stage.layout ∈ WebKit.wkStages ⟨0, .size, ℓ⟩
  cases ℓ <;> decide

end Fw.Guidance.Stability
