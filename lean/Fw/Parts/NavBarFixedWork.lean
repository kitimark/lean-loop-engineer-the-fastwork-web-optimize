import Fw.Parts.NavBarFixed
import Fw.Engine.WebKitSimple
/-!
# nav fixed size: flags, work and layer budget of the three arms
Work lemmas over `Fw.Engine.WebKit`; the layer budget is stated over census rows, the premises are named in the hypotheses.
-/
namespace Fw.Parts.NavBarFixedWork
open Fw.Engine Fw.Engine.WebKit Fw.Engine.WebKitSimple Fw.Parts.Nav Fw.Parts.NavClipBox Fw.Parts.NavBarFixed

/-- The arms of `nav` measured cumulatively. -/
inductive Arm where
  | faithful | clipBox | barFixed | logo3d
deriving Repr, DecidableEq

/-- The position of an arm in the cumulative order. -/
def Arm.rank : Arm → Nat
  | .faithful => 0 | .clipBox => 1 | .barFixed => 2 | .logo3d => 3

/-- Arm `a` includes the rules of arm `b`. -/
def Arm.has (a b : Arm) : Bool := decide (b.rank ≤ a.rank)

/-- `requires` of the flags: bar-fixed includes clip-box, logo-3d includes bar-fixed, and not the other way. -/
theorem requires_chain :
    Arm.has .barFixed .clipBox = true ∧ Arm.has .logo3d .barFixed = true ∧ Arm.has .logo3d .clipBox = true ∧
      Arm.has .clipBox .barFixed = false ∧ Arm.has .barFixed .logo3d = false := by decide

/-- The sequence of `--morph` values the nav writer produces; no arm changes the CSS-only rules' writer. -/
def writerOut (_ : Arm) (ms : List Rat) : List Rat := ms

/-- Every arm sees the sequence of the faithful arm, so the trajectory proofs of `MorphTween.tween` apply unchanged. -/
theorem writer_unchanged (a : Arm) (ms : List Rat) : writerOut a ms = writerOut .faithful ms := rfl

/-! ## Allocations of the nav backing per push -/

/-- Backing-store allocations over frames of the given sizes: a size change clears the buffers and allocates a front buffer
(`PlatformCALayerRemote.mm:333-355, 596-607`, `RemoteLayerWithRemoteRenderingBackingStore.mm:83-84, 126-151`); at a steady size
the second buffer is allocated once and the two swap (`ImageBufferSet.cpp:42-73`). Arguments: previous size, buffers held. -/
def allocs : Option Rat → Nat → List Rat → Nat
  | _, _, [] => 0
  | prev, held, s :: rest =>
    if prev == some s then
      (if held < 2 then 1 else 0) + allocs (some s) (if held < 2 then held + 1 else held) rest
    else 1 + allocs (some s) 1 rest

/-- A steady size allocates two buffers and no more, however many frames. -/
theorem allocs_steady (s : Rat) (n : Nat) : allocs (some s) 2 (List.replicate n s) = 0 := by
  induction n with
  | zero => rfl
  | succ n ih => simp [List.replicate_succ, allocs, ih]

/-- From a cold start a steady size allocates `min n 2` buffers. -/
theorem allocs_cold (s : Rat) (n : Nat) : allocs none 0 (List.replicate n s) = min n 2 := by
  cases n with
  | zero => rfl
  | succ n =>
    cases n with
    | zero => simp [allocs]
    | succ n =>
      have h : allocs (some s) 1 (List.replicate (n + 1) s) = 1 + allocs (some s) 2 (List.replicate n s) := by
        simp [List.replicate_succ, allocs]
      simp [List.replicate_succ, allocs, allocs_steady]

/-- Frames of a push whose size changes every frame, from sizes `k, k+1, ...` as rationals. -/
def growing (k : Nat) : Nat → List Rat
  | 0 => []
  | n + 1 => (k : Rat) :: growing (k + 1) n

/-- A size that changes every frame allocates a buffer every frame. -/
theorem allocs_growing (n k : Nat) (p : Option Rat) (held : Nat) (hp : p ≠ some (k : Rat)) :
    allocs p held (growing k n) = n := by
  induction n generalizing k p held with
  | zero => rfl
  | succ n ih =>
    have hne : ((k : Rat) == ((k + 1 : Nat) : Rat)) = false := by
      simp only [beq_eq_false_iff_ne]; intro h; have : (k : Rat) + 1 = k := by simpa using h.symm
      grind
    have h1 : (p == some (k : Rat)) = false := by simpa using hp
    have hp' : some (k : Rat) ≠ some ((k + 1 : Nat) : Rat) := by
      intro h; apply (beq_eq_false_iff_ne.mp hne); simpa using h
    simp only [growing, allocs, h1]
    simp [ih (k + 1) (some (k : Rat)) 1 hp']
    omega

/-- Per push of `n ≥ 3` frames the fixed nav allocates 2 buffers; a nav resized every frame allocates `n`. -/
theorem wk_allocs_push (n : Nat) (s : Rat) (h : 3 ≤ n) :
    allocs none 0 (List.replicate n s) = 2 ∧ allocs none 0 (growing 0 n) = n ∧ allocs none 0 (List.replicate n s) < n := by
  have a := allocs_cold s n
  have b := allocs_growing n 0 none 0 (by simp)
  refine ⟨by omega, b, by omega⟩

/-! ## Resize paint of the bar -/

/-- Number of size changes along a sequence of sizes. -/
def resizeCount : List Rat → Nat
  | a :: b :: rest => (if a == b then 0 else 1) + resizeCount (b :: rest)
  | _ => 0

/-- A constant size never resizes. -/
theorem resizeCount_const (ms : List Rat) (c : Rat) : resizeCount (ms.map fun _ => c) = 0 := by
  induction ms with
  | nil => rfl
  | cons m t ih =>
    cases t with
    | nil => rfl
    | cons m' t' => simp_all [resizeCount]

/-- Paint caused by the resizes of a push on a layer of `a` kpx with an attached store. -/
def pushResizePaint (draws delegates : Bool) (a : Nat) (sizes : List Rat) : Nat :=
  resizeCount sizes * resizePaint draws delegates true a

/-- The bar under `nav:bar-fixed` has the union width at every morph value, so a push causes no resize paint (premise: the bar is composited with its own store). -/
theorem bar_resizePaint_zero (v : Vp) (ms : List Rat) (a : Nat) :
    pushResizePaint true false a (ms.map (barW v)) = 0 := by
  have : ms.map (barW v) = ms.map fun _ => unionW v := rfl
  simp [pushResizePaint, this, resizeCount_const]

/-- The same push on the bar of the original repaints in full once per size change. -/
theorem bar_orig_resizes (a : Nat) (x y : Rat) (h : x ≠ y) :
    pushResizePaint true false a [x, y] = a := by
  simp [pushResizePaint, resizeCount, resizePaint, usesBacking, h]

/-! ## Logo layout units per frame -/

/-- The frame of the original logo: `left` moves an absolute box with no layer. -/
def logoLeftFrame : FrameIn WkProp := ⟨0, 0, 0, 0, [⟨1, .insetAbs, .none⟩], 0⟩

/-- The layer state of a logo moved by `translate3d` under a compositing policy: own layer iff the policy composites it. -/
def logoLayer (p : Policy) : LayerState := if composites p .transform3DFlat then .own else .layer

/-- The frame of the logo under `nav:logo-3d`. -/
def logo3dFrame (p : Policy) : FrameIn WkProp := ⟨0, 0, 0, 0, [⟨1, .transform, logoLayer p⟩], 0⟩

/-- Layout units of a frame (the stage rules do not depend on the mode). -/
def layoutUnits (f : FrameIn WkProp) : Nat := stageUnits webkit f .layout

/-- Under the Normal policy the logo layer is own and the frame has no layout unit; the original frame has one. -/
theorem logo3d_layout_normal : layoutUnits logoLeftFrame = 1 ∧ layoutUnits (logo3dFrame .normal) = 0 := by
  decide +kernel

/-- Under the Conservative policy the logo has a layer but is not composited: the frame keeps its layout unit, no saving. -/
theorem logo3d_layout_conservative : layoutUnits (logo3dFrame .conservative) = 1 := by
  decide +kernel

/-- The bar-fixed arm's logo (a `translate` on a layer that is not composited) keeps one layout unit: no layout saving before logo-3d. -/
theorem logo_translate_layout : layoutUnits ⟨0, 0, 0, 0, [⟨1, .transform, .layer⟩], 0⟩ = 1 := by
  decide +kernel

/-! ## Raster area -/

/-- Area in px² of a box. -/
def area (w h : Rat) : Rat := w * h

/-- The union box is never smaller than the pill, so a backing of the union is a trade unless the nav is a simple container. -/
theorem area_trade (v : Vp) (m : Rat) (h0 : 0 ≤ m) (h1 : m ≤ 1) (hv : pillH v ≤ panelH v) (hw0 : 0 ≤ pillW v) :
    area (navWidth v false m) (navHeight v m) ≤ area (unionW v) (unionH v) := by
  have hw := panel_ge_pill v
  have hph : 0 ≤ pillH v := by unfold pillH; cases phone v.w <;> simp <;> grind
  have a := Rat.mul_nonneg (show 0 ≤ panelW v - pillW v by grind) (show 0 ≤ 1 - m by grind)
  have a2 := Rat.mul_nonneg (show 0 ≤ panelW v - pillW v by grind) h0
  have b := Rat.mul_nonneg (show 0 ≤ panelH v - pillH v by grind) (show 0 ≤ 1 - m by grind)
  have b2 := Rat.mul_nonneg (show 0 ≤ panelH v - pillH v by grind) h0
  have wle : navWidth v false m ≤ unionW v := by unfold navWidth unionW expand; grind
  have wpos : 0 ≤ navWidth v false m := by unfold navWidth expand; grind
  have hle : navHeight v m ≤ unionH v := by
    unfold navHeight unionH; cases phone v.w <;> simp <;> grind
  have hpos : 0 ≤ navHeight v m := by unfold navHeight; grind
  unfold area
  have e1 := Rat.mul_le_mul_of_nonneg_left hle wpos
  have e2 := Rat.mul_le_mul_of_nonneg_left wle (show 0 ≤ unionH v by grind)
  grind

/-! ## Composited bar -/

/-- Whether `will-change: transform` on the bar composites it under a policy (`RenderLayerCompositor.cpp:3997-4018`, `composites`). -/
def barComposited (p : Policy) : Bool := composites p .willChange

/-- The bar premise of the simple container holds under the Normal policy and fails under the Conservative one. -/
theorem bar_normal_only : barComposited .normal = true ∧ barComposited .conservative = false := by decide

/-- Under the Conservative policy the bar is not composited, so the nav keeps painting its descendants (no simple container). -/
theorem conservative_not_simple (b : Box) (h : b.barComposited = barComposited .conservative) : drawsContent b = true :=
  bar_premise_needed b (h.trans bar_normal_only.2)

/-! ## Layer budget -/

/-- A census row: a layer's name, and its backing in kpx. -/
structure Row where
  name : String
  kpx : Nat
deriving Repr, DecidableEq

/-- Rows added by the arms on top of the faithful census while the nav morphs: the mask has no store, the bar and the logo have one each. -/
def added (a : Arm) (barKpx logoKpx : Nat) : List Row :=
  (if a.has .clipBox then [⟨"nav mask", 0⟩] else []) ++ (if a.has .barFixed then [⟨"nav bar", barKpx⟩] else []) ++
    (if a.has .logo3d then [⟨"logo", logoKpx⟩] else [])

/-- Backing added by an arm: only the bar and the logo layers carry a store. -/
def addedKpx (a : Arm) (barKpx logoKpx : Nat) : Nat := ((added a barKpx logoKpx).map Row.kpx).sum

/-- Layer budget: clip-box adds one layer and no backing, bar-fixed one layer with `barKpx`, logo-3d one layer with `logoKpx`. -/
theorem layer_budget (barKpx logoKpx : Nat) :
    ((added .clipBox barKpx logoKpx).length = 1 ∧ addedKpx .clipBox barKpx logoKpx = 0) ∧
    ((added .barFixed barKpx logoKpx).length = 2 ∧ addedKpx .barFixed barKpx logoKpx = barKpx) ∧
    ((added .logo3d barKpx logoKpx).length = 3 ∧ addedKpx .logo3d barKpx logoKpx = barKpx + logoKpx) := by
  simp [added, addedKpx, Arm.has, Arm.rank]

/-- Nav backing during the morph: the union area held by the original-style rounded nav, nothing once the nav is a simple container. -/
theorem nav_backing (a : Nat) :
    residentKpx (drawsContent navOrig) false a = a ∧ residentKpx (drawsContent navClip) false a = 0 :=
  ⟨(navClip_vs_orig false a).2.2.1, (navClip_vs_orig false a).1⟩

end Fw.Parts.NavBarFixedWork
