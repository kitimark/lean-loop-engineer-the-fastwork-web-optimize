import Lean.Data.Json
import Fw.Engine.Visual
import Fw.Engine.WebKit

/-! Fw.Gate.PathPix: one pinned-frame pixel cell (lane x viewport x pinned sample x declared layer mask) graded
E < E1 < Q < L, or invalid (task path-pix-core). -/

namespace Fw.Gate.PathPix
open Lean Fw.Engine
open Fw.Engine.WebKit (CssProp)

/-! ## Accelerated -/

/-- The 7 properties WebKit always accelerates: `"animation-wrapper-acceleration": "always"` at
`Source/WebCore/css/CSSProperties.json:7114,10263,10639,12112,12260,12281,12306@862f17d`. -/
def always : CssProp → Bool
  | .opacity | .filter | .backdropFilter | .transform | .translate | .scale | .rotate => true
  | _ => false

/-- Every keyframed property of a GPU-port candidate is one of the 7 in `always`. -/
def Accelerated (ps : List CssProp) : Prop := ∀ p ∈ ps, always p = true

/-- The decision for `Accelerated`. -/
def accelerated (ps : List CssProp) : Bool := ps.all always

theorem accelerated_iff (ps : List CssProp) : accelerated ps = true ↔ Accelerated ps := by
  simp [accelerated, Accelerated]

theorem always_iff_both_paths (p : CssProp) :
    always p = true ↔ ∀ path, WebKit.accelerated path p = true := by
  constructor
  · intro h path
    cases p <;> cases path <;> simp_all [always, WebKit.accelerated]
  · intro h
    have := h .legacy
    cases p <;> simp_all [always, WebKit.accelerated]

theorem offset_not_accelerated : ¬ Accelerated [.offset] := by
  simp [Accelerated, always]

theorem custom_not_accelerated (ps : List CssProp) : ¬ Accelerated (.custom :: ps) := by
  simp [Accelerated, always]

theorem accelerated_append (ps qs : List CssProp) :
    accelerated (ps ++ qs) = (accelerated ps && accelerated qs) := by
  simp [accelerated, List.all_append]

#guard accelerated [.transform, .opacity, .filter, .backdropFilter, .translate, .scale, .rotate]
#guard accelerated []
#guard !accelerated [.offset] && !accelerated [.transform, .clipPath] && !accelerated [.custom]
#guard !accelerated [.background, .color, .inset, .size, .strokeDashoffset]

/-! ## Grades -/

/-- A cell's grade: `e` byte-equal with the exact proof's premises closed, `e1` within 1 level under a proved
1-level bound, `q` a measured bound only, `l` a look change, `invalid` no verdict. -/
inductive Grade where
  | e | e1 | q | l | invalid
deriving DecidableEq, Repr, Inhabited

/-- The order E < E1 < Q < L; `invalid` has no rank. -/
def Grade.rank : Grade → Option Nat
  | .e => some 0 | .e1 => some 1 | .q => some 2 | .l => some 3 | .invalid => none

/-- The golden name of a grade. -/
def Grade.name : Grade → String
  | .e => "E" | .e1 => "E1" | .q => "Q" | .l => "L" | .invalid => "invalid"

theorem rank_order : [Grade.e, .e1, .q, .l].map Grade.rank = [some 0, some 1, some 2, some 3] := rfl

theorem rank_none_iff (g : Grade) : g.rank = none ↔ g = .invalid := by
  cases g <;> simp [Grade.rank]

/-! ## Measured counts -/

/-- Raw byte statistics of one image pair over one region: pixels where any channel differs, and the largest
channel difference in 8-bit levels. -/
structure Raw where
  changed : Nat
  maxDelta : Nat
deriving DecidableEq, Repr

/-- Every changed channel moved by at most 1 level. -/
def Raw.within1 (r : Raw) : Bool := r.maxDelta ≤ 1

theorem within1_iff (r : Raw) : r.within1 = true ↔ r.maxDelta ≤ 1 := by simp [Raw.within1]

/-- A consistent `Raw`: no changed pixel iff a zero largest difference, and that difference is at most 255. -/
def Raw.ok (r : Raw) : Bool := (r.changed == 0) == (r.maxDelta == 0) && r.maxDelta ≤ 255

/-- The path-only control arm P (the original with only the claimed layer forced onto its own layer) against arm A
inside the mask, with its own two-capture check. -/
structure Control where
  same : Bool
  raw : Raw
deriving DecidableEq, Repr

/-! ## Premises per claimed layer (design 3.4) -/

/-- The engine of a lane. -/
inductive Engine where
  | chromium | webkit
deriving DecidableEq, Repr

/-- A path premise or open exception of a claimed layer: P1 same layer tree and backing, P2 bit-equal value per
frame, P3 same sample point, P4 deterministic compositor, S1 origin on the device-pixel grid, T1 texel-centre
sampling, C1 text under a resampled transform, C2 raster scale, C5 fractional translate, C6 Core Animation blur. -/
inductive Premise where
  | p1 | p2 | p3 | p4 | s1 | t1 | c1 | c2 | c5 | c6
deriving DecidableEq, Repr

/-- The golden name of a premise. -/
def Premise.name : Premise → String
  | .p1 => "P1" | .p2 => "P2" | .p3 => "P3" | .p4 => "P4" | .s1 => "S1" | .t1 => "T1"
  | .c1 => "C1" | .c2 => "C2" | .c5 => "C5" | .c6 => "C6"

/-- The theorems that bound a layer's path by 1 level (allowlist): `doubleRound` is `double_round_le1`. -/
inductive Bound1 where
  | doubleRound
deriving DecidableEq, Repr

/-- One claimed layer of an arm pair: keyframed properties, a transform that scales or rotates, text inside, snap on,
on a compositor path in arm A or arm B, and the 1-level bound the part names. -/
structure Claim where
  props : List CssProp
  scales : Bool
  text : Bool
  snap : Bool
  compA : Bool
  compB : Bool
  bound : Option Bound1
deriving DecidableEq, Repr

/-- The claim moves its layer by an offset. -/
def Claim.translates (c : Claim) : Bool := c.props.any fun p => p == .transform || p == .translate || p == .offset

/-- The claim resamples its layer's bitmap by a scale or a rotation. -/
def Claim.resamples (c : Claim) : Bool := c.scales || c.props.any fun p => p == .scale || p == .rotate

/-- The claim animates a filter. -/
def Claim.filters (c : Claim) : Bool := c.props.any fun p => p == .filter || p == .backdropFilter

/-- The layer is on a compositor path in either arm. -/
def Claim.composited (c : Claim) : Bool := c.compA || c.compB

/-- `doubleRound` covers an opacity-only claim with no scale and no text. -/
def Bound1.covers : Bound1 → Claim → Bool
  | .doubleRound, c => !c.props.isEmpty && c.props.all (· == .opacity) && !c.scales && !c.text

/-- The premises a run must pass for one claimed layer on one engine (design 3.4). -/
def premises (eng : Engine) (c : Claim) : List Premise :=
  (if c.composited then [.p1] else []) ++ [.p2, .p3, .p4] ++
    (if c.snap then [.s1, .t1] else []) ++
    (if c.text && (c.resamples || (c.translates && !c.snap)) then [.c1] else []) ++
    (if c.resamples then [.c2] else []) ++
    (if c.translates && !c.snap then [.c5] else []) ++
    (if c.filters && eng == .webkit && c.composited then [.c6] else [])

theorem p1_mem_iff (eng : Engine) (c : Claim) : Premise.p1 ∈ premises eng c ↔ c.composited = true := by
  unfold premises; split <;> split <;> split <;> split <;> split <;> split <;> simp_all

theorem p234_mem (eng : Engine) (c : Claim) :
    Premise.p2 ∈ premises eng c ∧ Premise.p3 ∈ premises eng c ∧ Premise.p4 ∈ premises eng c := by
  unfold premises; simp

theorem premises_complete (eng : Engine) (c : Claim) (h : c.composited = true) :
    Premise.p1 ∈ premises eng c ∧ Premise.p2 ∈ premises eng c ∧ Premise.p3 ∈ premises eng c ∧
      Premise.p4 ∈ premises eng c :=
  ⟨(p1_mem_iff eng c).2 h, p234_mem eng c⟩

theorem s1_mem_iff (eng : Engine) (c : Claim) : Premise.s1 ∈ premises eng c ↔ c.snap = true := by
  unfold premises; split <;> split <;> split <;> split <;> split <;> split <;> simp_all

theorem t1_mem_iff (eng : Engine) (c : Claim) : Premise.t1 ∈ premises eng c ↔ c.snap = true := by
  unfold premises; split <;> split <;> split <;> split <;> split <;> split <;> simp_all

theorem c1_mem_iff (eng : Engine) (c : Claim) :
    Premise.c1 ∈ premises eng c ↔ (c.text && (c.resamples || (c.translates && !c.snap))) = true := by
  unfold premises; split <;> split <;> split <;> split <;> split <;> split <;> simp_all

theorem c2_mem_iff (eng : Engine) (c : Claim) : Premise.c2 ∈ premises eng c ↔ c.resamples = true := by
  unfold premises; split <;> split <;> split <;> split <;> split <;> split <;> simp_all

theorem c5_mem_iff (eng : Engine) (c : Claim) :
    Premise.c5 ∈ premises eng c ↔ (c.translates && !c.snap) = true := by
  unfold premises; split <;> split <;> split <;> split <;> split <;> split <;> simp_all

theorem c6_mem_iff (eng : Engine) (c : Claim) :
    Premise.c6 ∈ premises eng c ↔ (c.filters && eng == .webkit && c.composited) = true := by
  unfold premises; split <;> split <;> split <;> split <;> split <;> split <;> simp_all

theorem snap_drops_c5 (eng : Engine) (c : Claim) (h : c.snap = true) : Premise.c5 ∉ premises eng c := by
  rw [c5_mem_iff]; simp [h]

theorem chromium_no_c6 (c : Claim) : Premise.c6 ∉ premises .chromium c := by
  rw [c6_mem_iff]; simp

/-! ## Snap premises S1 and T1 -/

/-- The S1 tolerance in device pixels: print noise of a census float, far below the 1/64 px of a layout unit. -/
def gridDelta : Rat := 1 / 10000

/-- A device-pixel coordinate lies within `gridDelta` of an integer. -/
def onGrid (x : Rat) : Bool := decide (x - roundQ x ≤ gridDelta) && decide ((roundQ x : Rat) - x ≤ gridDelta)

theorem roundQ_err (x : Rat) : (roundQ x : Rat) - x ≤ 1 / 2 ∧ x - roundQ x < 1 / 2 := by
  unfold roundQ
  have a := Rat.floor_le (x + 1 / 2)
  have b := Rat.lt_floor_add_one (x + 1 / 2)
  constructor <;> grind

theorem grid_round (x δ : Rat) (z : Int) (hδ : δ < 1 / 2) (h1 : x - z ≤ δ) (h2 : (z : Rat) - x ≤ δ) :
    roundQ x = z := by
  unfold roundQ
  apply Int.le_antisymm
  · have : (x + 1 / 2).floor < z + 1 := Rat.floor_lt_iff.mpr (by rw [Rat.intCast_add]; grind)
    omega
  · exact Rat.le_floor_iff.mpr (by grind)

theorem onGrid_round (x : Rat) (h : onGrid x = true) : roundQ x = roundQ (roundQ x : Rat) ∧
    x - roundQ x ≤ gridDelta ∧ (roundQ x : Rat) - x ≤ gridDelta := by
  simp only [onGrid, Bool.and_eq_true, decide_eq_true_eq] at h
  exact ⟨(roundQ_int _).symm, h.1, h.2⟩

/-- Linear interpolation of a texel row at position `x`: the 1-D bilinear sample. -/
def lerpAt (I : Int → Rat) (x : Rat) : Rat :=
  (1 - (x - x.floor)) * I x.floor + (x - x.floor) * I (x.floor + 1)

theorem floor_intCast (z : Int) : (z : Rat).floor = z := by
  have := roundQ_int z
  apply Int.le_antisymm
  · have : (z : Rat).floor < z + 1 := Rat.floor_lt_iff.mpr (by rw [Rat.intCast_add]; grind)
    omega
  · exact Rat.le_floor_iff.mpr (by grind)

theorem bilin_at_grid (I : Int → Rat) (z : Int) : lerpAt I z = I z := by
  simp only [lerpAt, floor_intCast]
  grind

theorem floor_sub_int (x : Rat) (k : Int) : (x - k).floor = x.floor - k := by
  apply Int.le_antisymm
  · have a := Rat.floor_le x
    have b := Rat.lt_floor_add_one x
    have : (x - k).floor < x.floor - k + 1 :=
      Rat.floor_lt_iff.mpr (by push_cast; grind)
    omega
  · apply Rat.le_floor_iff.mpr
    have a := Rat.floor_le x
    push_cast; grind

theorem shift_sample (I : Int → Rat) (k : Int) (x : Rat) :
    lerpAt (fun j => I (j - k)) x = lerpAt I (x - k) := by
  simp only [lerpAt, floor_sub_int]
  have e1 : x.floor - k + 1 = x.floor + 1 - k := by omega
  rw [e1]
  push_cast
  grind

theorem snap_exact (I : Int → Rat) (k z : Int) : lerpAt (fun j => I (j - k)) z = I (z - k) := by
  rw [shift_sample]
  have : ((z : Rat) - k) = ((z - k : Int) : Rat) := by push_cast; rfl
  rw [this, bilin_at_grid]

#guard onGrid 99 && onGrid (99 + 1 / 20000) && onGrid (99 - 1 / 20000)
#guard !onGrid (99 + 1 / 2) && !onGrid (98 + 63 / 64) && !onGrid (1 / 3 * 3 + 1 / 1000)
#guard lerpAt (fun j => (j : Rat)) (5 / 2) == 5 / 2

/-! ## Near1 -/

/-- Two images (channel values in 8-bit levels, indexed by pixel and channel) differ by at most 1 level everywhere. -/
def Near1 {X : Type} (a b : X → Int) : Prop := ∀ x, a x - b x ≤ 1 ∧ b x - a x ≤ 1

theorem near1_refl {X : Type} (a : X → Int) : Near1 a a := fun _ => by omega

theorem near1_symm {X : Type} {a b : X → Int} (h : Near1 a b) : Near1 b a := fun x => (h x).symm

theorem near1_of_eq {X : Type} {a b : X → Int} (h : a = b) : Near1 a b := h ▸ near1_refl a

theorem double_round_le1 (a b : Rat) (h0 : 0 ≤ a) (h1 : a ≤ 1) :
    roundQ (a * roundQ (b * 255)) - roundQ (a * b * 255) ≤ 1 ∧
      roundQ (a * b * 255) - roundQ (a * roundQ (b * 255)) ≤ 1 := by
  have ⟨e1, e2⟩ := roundQ_err (b * 255)
  have k : a * b * 255 = a * (b * 255) := by grind
  rw [k]
  have u : a * ((roundQ (b * 255) : Rat) - b * 255) ≤ a * (1 / 2) := Rat.mul_le_mul_of_nonneg_left e1 h0
  have v : a * (b * 255 - roundQ (b * 255)) ≤ a * (1 / 2) :=
    Rat.mul_le_mul_of_nonneg_left (by grind) h0
  exact roundQ_close _ _ (by grind) (by grind)

/-- `PathPremises5` with the group-opacity exception C4 replaced by a 1-level raster bound: a path change of a box
with no LCD text, no compositor scale and no fractional translate moves no channel by more than 1 level. -/
structure PathPremisesNear1 {Env T : Type} (X : Type) (vp : Env → Rect) (o v : Env → T → Scene) where
  raster    : (BoxId → Thread) → Scene → X → Int
  lcdText   : BoxId → Bool
  compScale : BoxId → Bool
  fracXf    : BoxId → Bool
  pathO     : Env → T → BoxId → Thread
  pathV     : Env → T → BoxId → Thread
  shownO    : Env → T → X → Int
  shownV    : Env → T → X → Int
  raster_near1 : ∀ (p q : BoxId → Thread) (s : Scene),
    (∀ i, p i ≠ q i → lcdText i = false ∧ compScale i = false ∧ fracXf i = false) → Near1 (raster p s) (raster q s)
  c125 : ∀ env t i, pathO env t i ≠ pathV env t i → lcdText i = false ∧ compScale i = false ∧ fracXf i = false
  c3o : ∀ env t, shownO env t = raster (pathO env t) (visible (vp env) (o env t))
  c3v : ∀ env t, shownV env t = raster (pathV env t) (visible (vp env) (v env t))

theorem shown_near1 {X Env T : Type} {vp : Env → Rect} {o v : Env → T → Scene}
    (P : PathPremisesNear1 X vp o v) (h : VisSame E vp o v) : ∀ env t, Near1 (P.shownO env t) (P.shownV env t) := by
  intro env t
  rw [P.c3o, P.c3v, h env t]
  exact P.raster_near1 _ _ _ fun i hi => P.c125 env t i hi

theorem alphaToy_near1 (p q : BoxId → Thread) (g c : BoxId) (bg bc : BoxVis) (rest : Scene)
    (h0 : 0 ≤ bg.alpha) (h1 : bg.alpha ≤ 1) :
    alphaToy p ((g, bg) :: (c, bc) :: rest) - alphaToy q ((g, bg) :: (c, bc) :: rest) ≤ 1 ∧
      alphaToy q ((g, bg) :: (c, bc) :: rest) - alphaToy p ((g, bg) :: (c, bc) :: rest) ≤ 1 := by
  have d := double_round_le1 bg.alpha bc.alpha h0 h1
  have k : bg.alpha * bc.alpha * 255 = bg.alpha * (bc.alpha * 255) := by grind
  simp only [alphaToy]
  cases p c <;> cases q c <;> simp only [k] at d ⊢ <;> omega

/-! ## The cell -/

/-- One pinned-frame cell: the GitHub run id of its captures, the lane's engine and whether its captures are lossless
8-bit at device resolution, the claimed layer, whether arm A's and arm B's two captures are byte-identical, A vs B
outside every declared mask and inside this layer's mask, the control arm P, the census P1 witness (same layer tree
and backing size in both arms), the layer origin in CSS px with the device pixel ratio, the run id of the T1
measurement, and a stored review record accepting the layer's frame strips. -/
structure Cell where
  run : String
  engine : Engine
  lossless : Bool
  claim : Claim
  sameA : Bool
  sameB : Bool
  out : Raw
  inside : Raw
  control : Option Control
  p1 : Bool
  origin : Option (Rat × Rat)
  dpr : Nat
  t1 : Option String
  stripsAccepted : Bool
deriving DecidableEq, Repr

/-- S1: the census origin times the device pixel ratio is on the device-pixel grid on both axes. -/
def Cell.s1 (c : Cell) : Bool := c.origin.any fun (x, y) => onGrid (x * c.dpr) && onGrid (y * c.dpr)

/-- The cell can carry a verdict: a run id, lossless captures, two byte-identical captures in every arm (P4),
consistent counts, and S1 when snap is on. -/
def Cell.valid (c : Cell) : Bool :=
  c.run != "" && c.lossless && c.sameA && c.sameB && c.control.all (·.same) &&
    c.out.ok && c.inside.ok && c.control.all (·.raw.ok) && (!c.claim.snap || c.s1)

/-- Whether the run closes a premise: P1 by the census, P2 by the cell itself, P3 by the pinned sample, P4 by
`valid`, S1 by the census origin, T1 by a measurement run id; C1, C2, C5 and C6 stay open. -/
def Cell.closed (c : Cell) : Premise → Bool
  | .p1 => c.p1
  | .p2 | .p3 | .p4 => true
  | .s1 => c.s1
  | .t1 => c.t1.any (· != "")
  | .c1 | .c2 | .c5 | .c6 => false

/-- The cell's premise list on its lane's engine. -/
def Cell.premises (c : Cell) : List Premise := PathPix.premises c.engine c.claim

/-- Every premise is closed: byte equality follows from `shown_eq`/`shown_eq5`, not from the samples alone. -/
def Cell.exactBacked (c : Cell) : Bool := c.premises.all c.closed

/-- A proved 1-level bound covers the claim and every premise other than P1 is closed (`shown_near1`). -/
def Cell.near1Backed (c : Cell) : Bool :=
  c.claim.bound.any (·.covers c.claim) && (c.premises.filter (· != .p1)).all c.closed

/-- C1 is open and the user has not accepted the layer's strips. -/
def Cell.textHold (c : Cell) : Bool := c.premises.contains .c1 && !c.stripsAccepted

/-- Inside the mask, B differs from A no more than the control P does (measured path noise, run id `run`). -/
def Cell.withinNoise (c : Cell) : Bool :=
  c.control.any fun p => c.inside.changed ≤ p.raw.changed && c.inside.maxDelta ≤ p.raw.maxDelta

/-- **The cell decision.** -/
def grade (c : Cell) : Grade :=
  if !c.valid then .invalid
  else if c.out.changed != 0 then .l
  else if c.textHold then .l
  else if c.inside.changed == 0 && c.exactBacked then .e
  else if c.inside.within1 && c.near1Backed then .e1
  else if c.inside.within1 then .q
  else if c.withinNoise then .q
  else .l

theorem grade_invalid_iff (c : Cell) : grade c = .invalid ↔ c.valid = false := by
  unfold grade
  cases hv : c.valid
  · simp
  · simp only [Bool.not_true, Bool.false_eq_true, ↓reduceIte, reduceCtorEq, iff_false]
    repeat' split
    all_goals simp

theorem valid_iff (c : Cell) : c.valid = true ↔
    c.run ≠ "" ∧ c.lossless = true ∧ c.sameA = true ∧ c.sameB = true ∧ c.control.all (·.same) = true ∧
      c.out.ok = true ∧ c.inside.ok = true ∧ c.control.all (·.raw.ok) = true ∧ (c.claim.snap = true → c.s1 = true) := by
  simp only [Cell.valid, Bool.and_eq_true, bne_iff_ne, ne_eq, Bool.or_eq_true, Bool.not_eq_true']
  constructor
  · rintro ⟨⟨⟨⟨⟨⟨⟨⟨h1, h2⟩, h3⟩, h4⟩, h5⟩, h6⟩, h7⟩, h8⟩, h9⟩
    refine ⟨h1, h2, h3, h4, h5, h6, h7, h8, fun hs => ?_⟩
    rcases h9 with h9 | h9 <;> simp_all
  · rintro ⟨h1, h2, h3, h4, h5, h6, h7, h8, h9⟩
    refine ⟨⟨⟨⟨⟨⟨⟨⟨h1, h2⟩, h3⟩, h4⟩, h5⟩, h6⟩, h7⟩, h8⟩, ?_⟩
    cases hs : c.claim.snap
    · exact Or.inl rfl
    · exact Or.inr (h9 hs)

theorem inside_zero_iff (c : Cell) (hv : c.valid = true) : c.inside.changed = 0 ↔ c.inside.maxDelta = 0 := by
  have h := ((valid_iff c).1 hv).2.2.2.2.2.2.1
  simp only [Raw.ok, Bool.and_eq_true] at h
  have h1 := h.1
  by_cases a : c.inside.changed = 0 <;> by_cases b : c.inside.maxDelta = 0 <;> simp_all

theorem snap_needs_s1 (c : Cell) (hv : c.valid = true) (hs : c.claim.snap = true) : c.s1 = true :=
  ((valid_iff c).1 hv).2.2.2.2.2.2.2.2 hs

theorem outside_change_is_l (c : Cell) (hv : c.valid = true) (h : c.out.changed ≠ 0) : grade c = .l := by
  simp [grade, hv, h]

theorem text_hold_is_l (c : Cell) (hv : c.valid = true) (h : c.textHold = true) : grade c = .l := by
  simp [grade, hv, h]

theorem grade_e_iff (c : Cell) : grade c = .e ↔
    c.valid = true ∧ c.out.changed = 0 ∧ c.textHold = false ∧ c.inside.changed = 0 ∧ c.exactBacked = true := by
  unfold grade
  by_cases hv : c.valid <;> by_cases ho : c.out.changed = 0 <;> by_cases ht : c.textHold <;>
    by_cases hi : c.inside.changed = 0 <;> by_cases hx : c.exactBacked <;> by_cases hm : c.inside.within1 <;>
    by_cases hn : c.near1Backed <;> by_cases hw : c.withinNoise <;> simp_all

theorem grade_e1_iff (c : Cell) : grade c = .e1 ↔
    c.valid = true ∧ c.out.changed = 0 ∧ c.textHold = false ∧ ¬ (c.inside.changed = 0 ∧ c.exactBacked = true) ∧
      c.inside.within1 = true ∧ c.near1Backed = true := by
  unfold grade
  by_cases hv : c.valid <;> by_cases ho : c.out.changed = 0 <;> by_cases ht : c.textHold <;>
    by_cases hi : c.inside.changed = 0 <;> by_cases hx : c.exactBacked <;> by_cases hm : c.inside.within1 <;>
    by_cases hn : c.near1Backed <;> by_cases hw : c.withinNoise <;> simp_all

theorem measured_within1_is_q (c : Cell) (hv : c.valid = true) (ho : c.out.changed = 0) (ht : c.textHold = false)
    (hx : ¬ (c.inside.changed = 0 ∧ c.exactBacked = true)) (hm : c.inside.within1 = true)
    (hn : c.near1Backed = false) : grade c = .q := by
  unfold grade
  by_cases hi : c.inside.changed = 0 <;> simp_all

theorem noise_is_q (c : Cell) (hv : c.valid = true) (ho : c.out.changed = 0) (ht : c.textHold = false)
    (hm : 1 < c.inside.maxDelta) (hw : c.withinNoise = true) : grade c = .q := by
  have hi : c.inside.changed ≠ 0 := fun h0 => by have := (inside_zero_iff c hv).1 h0; omega
  have hm' : c.inside.within1 = false := by simp [Raw.within1]; omega
  simp [grade, hv, ho, ht, hi, hw, hm']

theorem above_noise_is_l (c : Cell) (hv : c.valid = true) (hm : 1 < c.inside.maxDelta)
    (hw : c.withinNoise = false) : grade c = .l := by
  have hi : c.inside.changed ≠ 0 := fun h0 => by have := (inside_zero_iff c hv).1 h0; omega
  have hm' : c.inside.within1 = false := by simp [Raw.within1]; omega
  unfold grade
  by_cases ho : c.out.changed = 0 <;> by_cases ht : c.textHold <;> simp_all

theorem e_byte_equal (c : Cell) (h : grade c = .e) : c.out.changed = 0 ∧ c.inside.changed = 0 := by
  have := (grade_e_iff c).1 h; exact ⟨this.2.1, this.2.2.2.1⟩

theorem e1_proved (c : Cell) (h : grade c = .e1) :
    c.inside.maxDelta ≤ 1 ∧ ∃ b, c.claim.bound = some b ∧ b.covers c.claim = true := by
  have := (grade_e1_iff c).1 h
  refine ⟨(within1_iff _).1 this.2.2.2.2.1, ?_⟩
  have hn := this.2.2.2.2.2
  simp only [Cell.near1Backed, Bool.and_eq_true, Option.any_eq_true] at hn
  obtain ⟨b, hb, hc⟩ := hn.1
  exact ⟨b, hb, hc⟩

theorem unbounded_not_e1 (c : Cell) (h : c.claim.bound = none) : grade c ≠ .e1 := by
  intro he
  obtain ⟨_, b, hb, _⟩ := e1_proved c he
  simp_all

theorem exactBacked_closes (c : Cell) (h : c.exactBacked = true) (p : Premise) (hp : p ∈ c.premises) :
    c.closed p = true := by
  simp only [Cell.exactBacked, List.all_eq_true] at h; exact h p hp

theorem not_composited_not_e (c : Cell) (hc : c.claim.composited = true) (hp : c.p1 = false) : grade c ≠ .e := by
  intro he
  have hx := ((grade_e_iff c).1 he).2.2.2.2
  have := exactBacked_closes c hx .p1 ((p1_mem_iff c.engine c.claim).2 hc)
  simp_all [Cell.closed]

theorem open_not_e (c : Cell) (p : Premise) (hp : p ∈ c.premises) (ho : c.closed p = false) : grade c ≠ .e := by
  intro he
  have := exactBacked_closes c ((grade_e_iff c).1 he).2.2.2.2 p hp
  simp_all

theorem ca_blur_not_e (c : Cell) (h : (c.claim.filters && c.engine == .webkit && c.claim.composited) = true) :
    grade c ≠ .e ∧ grade c ≠ .e1 := by
  have hm : Premise.c6 ∈ c.premises := (c6_mem_iff c.engine c.claim).2 h
  refine ⟨open_not_e c .c6 hm rfl, fun he1 => ?_⟩
  have hn := ((grade_e1_iff c).1 he1).2.2.2.2.2
  simp only [Cell.near1Backed, Bool.and_eq_true, List.all_eq_true, List.mem_filter, bne_iff_ne, ne_eq,
    and_imp] at hn
  have := hn.2 .c6 hm (by decide)
  simp [Cell.closed] at this

theorem fractional_translate_not_e (c : Cell) (h : (c.claim.translates && !c.claim.snap) = true) : grade c ≠ .e :=
  open_not_e c .c5 ((c5_mem_iff c.engine c.claim).2 h) rfl

theorem text_fractional_is_l (c : Cell) (hv : c.valid = true) (htx : c.claim.text = true)
    (htr : c.claim.translates = true) (hs : c.claim.snap = false) (ha : c.stripsAccepted = false) :
    grade c = .l := by
  apply text_hold_is_l c hv
  have : Premise.c1 ∈ c.premises := (c1_mem_iff c.engine c.claim).2 (by simp [htx, htr, hs])
  simp [Cell.textHold, ha, this]

/-- `c` with its control arm replaced. -/
def Cell.withControl (c : Cell) (p : Control) : Cell := { c with control := some p }

theorem grade_noise_mono (c : Cell) (p p' : Control) (hc : c.control = some p) (hs : p'.same = p.same)
    (hok : p'.raw.ok = true) (h1 : p.raw.changed ≤ p'.raw.changed) (h2 : p.raw.maxDelta ≤ p'.raw.maxDelta)
    (hq : grade c = .q) : grade (c.withControl p') = .q := by
  have hv : c.valid = true := by
    cases h : c.valid
    · have := (grade_invalid_iff c).2 h; simp_all
    · rfl
  have hv' : (c.withControl p').valid = true := by
    have := (valid_iff c).1 hv
    apply (valid_iff _).2
    simp only [Cell.withControl, Cell.s1, Option.all_some] at this ⊢
    simp_all
  have hw : c.withinNoise = true → (c.withControl p').withinNoise = true := by
    have e : (c.withControl p').withinNoise =
        (decide (c.inside.changed ≤ p'.raw.changed) && decide (c.inside.maxDelta ≤ p'.raw.maxDelta)) := rfl
    rw [e]
    simp only [Cell.withinNoise, hc, Option.any_some, Bool.and_eq_true, decide_eq_true_eq]
    intro h
    exact ⟨by omega, by omega⟩
  have e1 : (c.withControl p').out = c.out := rfl
  have e2 : (c.withControl p').inside = c.inside := rfl
  have e3 : (c.withControl p').textHold = c.textHold := rfl
  have e4 : (c.withControl p').exactBacked = c.exactBacked := rfl
  have e5 : (c.withControl p').near1Backed = c.near1Backed := rfl
  unfold grade at hq ⊢
  rw [e1, e2, e3, e4, e5, hv']
  rw [hv] at hq
  by_cases ho : c.out.changed = 0 <;> by_cases ht : c.textHold <;> by_cases hi : c.inside.changed = 0 <;>
    by_cases hx : c.exactBacked <;> by_cases hm : c.inside.within1 <;> by_cases hn : c.near1Backed <;>
    by_cases hn' : c.withinNoise <;> simp_all

def Raw.le (a b : Raw) : Bool := a.changed ≤ b.changed && a.maxDelta ≤ b.maxDelta

theorem Raw.le_refl (a : Raw) : a.le a = true := by simp [Raw.le]

theorem Raw.le_trans (a b c : Raw) (h1 : a.le b = true) (h2 : b.le c = true) : a.le c = true := by
  simp only [Raw.le, Bool.and_eq_true, decide_eq_true_eq] at *
  omega

structure Floor where
  valid : Bool
  out : Raw
  inside : Raw
deriving DecidableEq, Repr

def Cell.floor (c : Cell) : Floor := ⟨c.valid, c.out, c.inside⟩

def Cell.withinFloor (c : Cell) (f : Floor) : Bool := f.valid && c.out.le f.out && c.inside.le f.inside

def gradeRel (c : Cell) (f : Option Floor) (live : Bool) : Grade :=
  if !live then .invalid
  else match grade c with
    | .l => if !c.textHold && f.any c.withinFloor then .q else .l
    | g => g

theorem gradeRel_not_live (c : Cell) (f : Option Floor) : gradeRel c f false = .invalid := by
  simp [gradeRel]

theorem gradeRel_no_floor (c : Cell) : gradeRel c none true = grade c := by
  unfold gradeRel
  cases h : grade c <;> simp

theorem gradeRel_of_ne_l (c : Cell) (f : Option Floor) (h : grade c ≠ .l) : gradeRel c f true = grade c := by
  unfold gradeRel
  cases hg : grade c <;> simp_all

theorem gradeRel_q_of_floor (c : Cell) (f : Floor) (hl : grade c = .l) (ht : c.textHold = false)
    (hw : c.withinFloor f = true) : gradeRel c (some f) true = .q := by
  simp [gradeRel, hl, ht, hw]

theorem gradeRel_l_of_text (c : Cell) (f : Option Floor) (hl : grade c = .l) (ht : c.textHold = true) :
    gradeRel c f true = .l := by
  simp [gradeRel, hl, ht]

theorem gradeRel_l_of_above (c : Cell) (f : Floor) (hl : grade c = .l) (hw : c.withinFloor f = false) :
    gradeRel c (some f) true = .l := by
  simp [gradeRel, hl, hw]

theorem gradeRel_l_of_invalid_floor (c : Cell) (f : Floor) (hl : grade c = .l) (hf : f.valid = false) :
    gradeRel c (some f) true = .l := by
  apply gradeRel_l_of_above c f hl
  simp [Cell.withinFloor, hf]

theorem gradeRel_e_iff (c : Cell) (f : Option Floor) (live : Bool) :
    gradeRel c f live = .e ↔ live = true ∧ grade c = .e := by
  cases live
  · simp [gradeRel]
  · by_cases hl : grade c = .l
    · by_cases hq : (!c.textHold && f.any c.withinFloor) = true <;> simp [gradeRel, hl, hq]
    · rw [gradeRel_of_ne_l c f hl]; simp

theorem gradeRel_invalid_iff (c : Cell) (f : Option Floor) (live : Bool) :
    gradeRel c f live = .invalid ↔ live = false ∨ c.valid = false := by
  cases live
  · simp [gradeRel]
  · by_cases hl : grade c = .l
    · have hv : c.valid = true := by
        cases h : c.valid
        · have := (grade_invalid_iff c).2 h; rw [hl] at this; cases this
        · rfl
      by_cases hq : (!c.textHold && f.any c.withinFloor) = true <;> simp [gradeRel, hl, hq, hv]
    · rw [gradeRel_of_ne_l c f hl]; simp [grade_invalid_iff]

inductive Why where
  | outside | text | inside
deriving DecidableEq, Repr

def Why.name : Why → String
  | .outside => "outside" | .text => "text" | .inside => "inside"

def whyL (c : Cell) (f : Option Floor) (live : Bool) : Option Why :=
  if gradeRel c f live = .l then
    if c.out.changed != 0 then some .outside else if c.textHold then some .text else some .inside
  else none

theorem whyL_isSome_iff (c : Cell) (f : Option Floor) (live : Bool) :
    (whyL c f live).isSome = true ↔ gradeRel c f live = .l := by
  unfold whyL
  by_cases h : gradeRel c f live = .l <;> by_cases ho : c.out.changed = 0 <;> by_cases ht : c.textHold <;> simp_all

theorem whyL_outside (c : Cell) (f : Option Floor) (live : Bool) (hl : gradeRel c f live = .l)
    (ho : c.out.changed ≠ 0) : whyL c f live = some .outside := by
  simp [whyL, hl, ho]

theorem whyL_text (c : Cell) (f : Option Floor) (live : Bool) (hl : gradeRel c f live = .l)
    (ho : c.out.changed = 0) (ht : c.textHold = true) : whyL c f live = some .text := by
  simp [whyL, hl, ho, ht]

theorem whyL_inside (c : Cell) (f : Option Floor) (live : Bool) (hl : gradeRel c f live = .l)
    (ho : c.out.changed = 0) (ht : c.textHold = false) : whyL c f live = some .inside := by
  simp [whyL, hl, ho, ht]

def cssName : CssProp → String
  | .transform => "transform" | .translate => "translate" | .scale => "scale" | .rotate => "rotate"
  | .opacity => "opacity" | .filter => "filter" | .backdropFilter => "backdrop-filter" | .offset => "offset"
  | .clipPath => "clip-path" | .background => "background" | .color => "color" | .inset => "inset"
  | .size => "size" | .strokeDashoffset => "stroke-dashoffset" | .custom => "custom"

/-- The golden name of an engine. -/
def Engine.name : Engine → String
  | .chromium => "chromium" | .webkit => "webkit"

/-- A golden `Raw` object. -/
def Raw.json (r : Raw) : Json := Json.mkObj [("changed", toJson r.changed), ("maxDelta", toJson r.maxDelta)]

/-- A golden claim object. -/
def Claim.json (c : Claim) : Json :=
  Json.mkObj [("props", toJson (c.props.map cssName)), ("scales", toJson c.scales), ("text", toJson c.text),
    ("snap", toJson c.snap), ("compA", toJson c.compA), ("compB", toJson c.compB),
    ("bound", match c.bound with | some .doubleRound => "doubleRound" | none => Json.null)]

/-- A golden cell object; origin coordinates are rationals written `n` or `n/d`. -/
def Cell.json (c : Cell) : Json :=
  Json.mkObj [("run", toJson c.run), ("engine", toJson c.engine.name), ("lossless", toJson c.lossless),
    ("claim", c.claim.json), ("sameA", toJson c.sameA), ("sameB", toJson c.sameB), ("out", c.out.json),
    ("inside", c.inside.json),
    ("control", match c.control with
      | some p => Json.mkObj [("same", toJson p.same), ("raw", p.raw.json)]
      | none => Json.null),
    ("p1", toJson c.p1),
    ("origin", match c.origin with
      | some (x, y) => toJson [toString x, toString y]
      | none => Json.null),
    ("dpr", toJson c.dpr), ("t1", match c.t1 with | some r => toJson r | none => Json.null),
    ("stripsAccepted", toJson c.stripsAccepted)]

def Floor.json (f : Floor) : Json := Json.mkObj [("valid", toJson f.valid), ("out", f.out.json), ("inside", f.inside.json)]

def opacityClaim : Claim := ⟨[.opacity], false, false, false, false, true, none⟩

/-- A translate claim, on the compositor in arm B only. -/
def moveClaim : Claim := ⟨[.transform], false, false, false, false, true, none⟩

/-- A valid Chromium cell for `cl` with the given counts and no control, census origin or snap witness. -/
def mkCell (cl : Claim) (out inside : Raw) : Cell :=
  ⟨"1001", .chromium, true, cl, true, true, out, inside, none, false, none, 3, none, false⟩

/-- The golden grade cases: a name and a cell. -/
def gradeCases : List (String × Cell) :=
  let z : Raw := ⟨0, 0⟩
  let one : Raw := ⟨120, 1⟩
  let two : Raw := ⟨80, 2⟩
  let both := { opacityClaim with compA := true }
  let dr := { opacityClaim with bound := some .doubleRound }
  let snapMove := { moveClaim with compA := true, snap := true }
  let blur : Claim := ⟨[.filter], false, false, false, true, true, none⟩
  let grid : Option (Rat × Rat) := some (100 / 3, 12)
  let snapAt (cl : Claim) (inside : Raw) (o : Option (Rat × Rat)) (t : Option String) : Cell :=
    { mkCell cl z inside with p1 := true, origin := o, t1 := t }
  [("both composited, P1 witnessed, byte-equal", { mkCell both z z with p1 := true }),
   ("port composited, P1 not witnessed, byte-equal", mkCell opacityClaim z z),
   ("double-rounded opacity within 1 with the proved bound", mkCell dr z one),
   ("byte-equal under the proved bound, P1 not witnessed", mkCell dr z z),
   ("opacity within 1 without a proved bound", mkCell opacityClaim z one),
   ("2 levels inside the control's noise", { mkCell dr z two with control := some ⟨true, ⟨200, 2⟩⟩ }),
   ("2 levels above the control's max delta", { mkCell dr z two with control := some ⟨true, ⟨200, 1⟩⟩ }),
   ("2 levels on more pixels than the control", { mkCell dr z two with control := some ⟨true, ⟨40, 3⟩⟩ }),
   ("2 levels without a control", mkCell dr z two),
   ("change outside the masks", mkCell both one z),
   ("arm A captures differ", { mkCell both z z with sameA := false }),
   ("arm B captures differ", { mkCell both z z with sameB := false }),
   ("control captures differ", { mkCell dr z one with control := some ⟨false, ⟨200, 2⟩⟩ }),
   ("lossy lane", { mkCell both z z with lossless := false, p1 := true }),
   ("no run id", { mkCell both z z with run := "", p1 := true }),
   ("changed pixels with a zero max delta", mkCell both z ⟨5, 0⟩),
   ("max delta above 255", mkCell both z ⟨5, 256⟩),
   ("snap on, origin half a device pixel off", snapAt snapMove z (some (101 / 6, 0)) (some "1002")),
   ("snap on, no census origin", snapAt snapMove z none (some "1002")),
   ("snap on, S1 and T1 hold, byte-equal", snapAt snapMove z grid (some "1002")),
   ("snap on, S1 holds, T1 not measured", snapAt snapMove z grid none),
   ("fractional translate, byte-equal", { mkCell { moveClaim with compA := true } z z with p1 := true }),
   ("text under a fractional translate, strips not accepted", mkCell { moveClaim with text := true } z z),
   ("text under a fractional translate, strips accepted",
    { mkCell { moveClaim with text := true } z one with stripsAccepted := true }),
   ("text under a snapped translate, S1 and T1 hold", snapAt { snapMove with text := true } z grid (some "1002")),
   ("WebKit Core Animation blur, byte-equal", { mkCell blur z z with engine := .webkit, p1 := true }),
   ("Chromium composited blur, byte-equal", { mkCell blur z z with p1 := true }),
   ("scale, byte-equal", { mkCell { moveClaim with compA := true, scales := true } z z with p1 := true }),
   ("not composited in either arm, byte-equal", mkCell { opacityClaim with compB := false } z z),
   ("bound named on a translate claim, within 1", mkCell { moveClaim with bound := some .doubleRound } z one),
   ("double-rounded opacity over text within 1", mkCell { dr with text := true } z one)]

/-- The golden `accelerated` cases. -/
def accelCases : List (List CssProp) :=
  [[.transform, .opacity], [.filter, .backdropFilter], [.translate, .scale, .rotate], [], [.offset],
   [.transform, .clipPath], [.custom], [.background], [.color, .opacity], [.inset], [.size], [.strokeDashoffset]]

/-- The golden premise-list cases: a name, an engine and a claim. -/
def premiseCases : List (String × Engine × Claim) :=
  [("opacity, port composited", .chromium, opacityClaim),
   ("opacity, neither arm composited", .chromium, { opacityClaim with compB := false }),
   ("translate, snap off", .webkit, moveClaim),
   ("translate, snap on", .webkit, { moveClaim with snap := true }),
   ("text under translate, snap off", .webkit, { moveClaim with text := true }),
   ("text under translate, snap on", .webkit, { moveClaim with text := true, snap := true }),
   ("text under scale, snap on", .chromium, { moveClaim with text := true, snap := true, scales := true }),
   ("filter on WebKit", .webkit, ⟨[.filter], false, false, false, false, true, none⟩),
   ("filter on Chromium", .chromium, ⟨[.filter], false, false, false, false, true, none⟩),
   ("backdrop-filter on WebKit, not composited", .webkit, ⟨[.backdropFilter], false, false, false, false, false, none⟩),
   ("rotate", .chromium, ⟨[.rotate], false, false, false, true, true, none⟩)]


def relCases : List (String × Cell × Option Floor × Bool) :=
  let z : Raw := ⟨0, 0⟩
  let fl (v : Bool) (o i : Raw) : Option Floor := some ⟨v, o, i⟩
  let plain := mkCell { opacityClaim with compA := true, props := [.opacity, .translate] } z z
  let txt := mkCell { moveClaim with text := true } z ⟨30, 4⟩
  let big := mkCell { moveClaim with compA := true } z ⟨30, 4⟩
  [("byte-equal E stays E under a floor", ({ mkCell { opacityClaim with compA := true } z z with p1 := true }, fl true ⟨9, 9⟩ ⟨9, 9⟩, true)),
   ("L inside the floor drops to Q", (big, fl true ⟨0, 0⟩ ⟨30, 4⟩, true)),
   ("L with a pixel more than the floor stays L", (big, fl true ⟨0, 0⟩ ⟨29, 4⟩, true)),
   ("L with a larger delta than the floor stays L", (big, fl true ⟨0, 0⟩ ⟨40, 3⟩, true)),
   ("L with an invalid floor stays L", (big, fl false ⟨0, 0⟩ ⟨99, 99⟩, true)),
   ("L without a floor stays L", (big, none, true)),
   ("text hold stays L inside the floor", (txt, fl true ⟨0, 0⟩ ⟨99, 99⟩, true)),
   ("outside change within the floor drops to Q", ({ big with out := ⟨5, 2⟩ }, fl true ⟨5, 2⟩ ⟨30, 4⟩, true)),
   ("outside change above the floor stays L", ({ big with out := ⟨6, 2⟩ }, fl true ⟨5, 2⟩ ⟨30, 4⟩, true)),
   ("Q stays Q", ({ plain with inside := ⟨10, 1⟩ }, fl true z z, true)),
   ("invalid cell stays invalid", ({ big with sameB := false }, fl true ⟨99, 99⟩ ⟨99, 99⟩, true)),
   ("arm not live is invalid", ({ mkCell { opacityClaim with compA := true } z z with p1 := true }, fl true ⟨9, 9⟩ ⟨9, 9⟩, false)),
   ("L outside with text hold is outside", ({ txt with out := ⟨1, 1⟩ }, fl true ⟨0, 0⟩ ⟨99, 99⟩, true))]

def regionCases : List (List ((Nat × Nat) × (Nat × Nat)) × Nat × Nat × Nat) :=
  let a : (Nat × Nat) × (Nat × Nat) := ((10, 20), (10, 20))
  let b : (Nat × Nat) × (Nat × Nat) := ((15, 30), (15, 30))
  [([a, b], 0, 12, 12), ([a, b], 0, 17, 17), ([a, b], 0, 25, 25), ([a, b], 0, 40, 40), ([a, b], 1, 17, 17),
   ([a], 0, 20, 10), ([], 0, 0, 0)]

def exitCases : List (Nat × Nat) := [(0, 600), (0, 932), (300, 664), (0, 40), (12, 1688)]

def exitClaimCases : List (String × Bool) :=
  [("hero_copy", true), ("hero_copy", false), ("hero.cue_cue", true), ("hero.cue_cue", false),
   ("hero.orbit_card", true), ("hero.orbit_card", false), ("hero.deck_article", true), ("nav_bar", true)]

def offsetAt (maxY i : Nat) : Nat := i * maxY / 8

def offsets (maxY : Nat) : List Nat := (List.range 9).map (offsetAt maxY)

theorem offsets_length (maxY : Nat) : (offsets maxY).length = 9 := by simp [offsets]

theorem offsetAt_zero (maxY : Nat) : offsetAt maxY 0 = 0 := by simp [offsetAt]

theorem offsetAt_last (maxY : Nat) : offsetAt maxY 8 = maxY := by unfold offsetAt; omega

theorem offsetAt_mono (maxY i j : Nat) (h : i ≤ j) : offsetAt maxY i ≤ offsetAt maxY j :=
  Nat.div_le_div_right (Nat.mul_le_mul_right maxY h)

theorem offsetAt_le (maxY i : Nat) (h : i ≤ 8) : offsetAt maxY i ≤ maxY := by
  have := Nat.mul_le_mul_right maxY h
  unfold offsetAt; omega

def clampN (n : Nat) (v : Int) : Nat := (max 0 (min (n : Int) v)).toNat

def span (dpr n : Nat) (lo : Int) (len : Nat) : Nat × Nat :=
  (clampN n (lo * dpr / 1000000 - 1), clampN n (-((-((lo + len) * dpr)) / 1000000) + 1))

def Hit (dpr : Nat) (lo : Int) (len : Nat) (d : Int) : Prop :=
  d * 1000000 < (lo + len) * dpr ∧ lo * dpr < (d + 1) * 1000000

theorem span_le (dpr n : Nat) (lo : Int) (len : Nat) : (span dpr n lo len).1 ≤ (span dpr n lo len).2 := by
  unfold span clampN
  have h : 0 ≤ (len : Int) * dpr := Int.mul_nonneg (by omega) (by omega)
  have : (lo + len) * dpr = lo * dpr + len * dpr := by rw [Int.add_mul]
  generalize lo * dpr = a at *
  generalize (len : Int) * dpr = c at *
  omega

theorem span_le_n (dpr n : Nat) (lo : Int) (len : Nat) : (span dpr n lo len).2 ≤ n := by
  unfold span clampN; omega

theorem span_covers (dpr n : Nat) (lo : Int) (len : Nat) (c d : Nat) (hd : Hit dpr lo len d) (hc : c < n)
    (hn : (d : Int) ≤ c + 1) (hp : (c : Int) ≤ d + 1) :
    (span dpr n lo len).1 ≤ c ∧ c < (span dpr n lo len).2 := by
  obtain ⟨h1, h2⟩ := hd
  unfold span clampN
  have : (lo + len) * dpr = lo * dpr + len * dpr := by rw [Int.add_mul]
  generalize lo * dpr = a at *
  generalize (len : Int) * dpr = e at *
  generalize (lo + len) * dpr = b at *
  omega

structure Box where
  x : Int
  y : Int
  w : Nat
  h : Nat
deriving DecidableEq, Repr

def mask (dpr fw fh : Nat) (b : Box) : (Nat × Nat) × (Nat × Nat) := (span dpr fw b.x b.w, span dpr fh b.y b.h)

def inMask (m : (Nat × Nat) × (Nat × Nat)) (c r : Nat) : Bool :=
  decide (m.1.1 ≤ c && c < m.1.2 && m.2.1 ≤ r && r < m.2.2)

def rawOf (px : List Nat) : Raw := ⟨(px.filter (· != 0)).length, px.foldl max 0⟩

theorem rawOf_ok (px : List Nat) (h : ∀ d ∈ px, d ≤ 255) : (rawOf px).ok = true := by
  have hmax : ∀ (l : List Nat) (a : Nat), (∀ d ∈ l, d ≤ 255) → a ≤ 255 → l.foldl max a ≤ 255 := by
    intro l; induction l with
    | nil => intro a _ ha; simpa using ha
    | cons x t ih =>
      intro a hl ha
      simp only [List.foldl_cons]
      exact ih _ (fun d hd => hl d (List.mem_cons_of_mem _ hd)) (by
        have := hl x (List.mem_cons_self ..); omega)
  have hz : ∀ (l : List Nat) (a : Nat), l.foldl max a = 0 ↔ a = 0 ∧ ∀ d ∈ l, d = 0 := by
    intro l; induction l with
    | nil => intro a; simp
    | cons x t ih =>
      intro a
      simp only [List.foldl_cons, ih, List.mem_cons, forall_eq_or_imp]
      have : max a x = 0 ↔ a = 0 ∧ x = 0 := by omega
      rw [this]; exact and_assoc
  have hc : (px.filter (· != 0)).length = 0 ↔ ∀ d ∈ px, d = 0 := by
    simp [List.filter_eq_nil_iff]
  have h1 := hmax px 0 h (by omega)
  have h2 := hz px 0
  have e : ((px.filter (· != 0)).length == 0) = (px.foldl max 0 == 0) := by
    apply Bool.eq_iff_iff.mpr
    simp only [beq_iff_eq]
    rw [hc, h2]
    simp
  unfold rawOf Raw.ok
  rw [e]
  simp [h1]

def inAny (ms : List ((Nat × Nat) × (Nat × Nat))) (c r : Nat) : Bool := ms.any (inMask · c r)

theorem inAny_nil (c r : Nat) : inAny [] c r = false := rfl

theorem inAny_iff (ms : List ((Nat × Nat) × (Nat × Nat))) (c r : Nat) :
    inAny ms c r = true ↔ ∃ m ∈ ms, inMask m c r = true := by
  simp [inAny]

inductive Region where
  | inside | other | out
deriving DecidableEq, Repr

def Region.name : Region → String
  | .inside => "inside" | .other => "other" | .out => "out"

def region (ms : List ((Nat × Nat) × (Nat × Nat))) (m : (Nat × Nat) × (Nat × Nat)) (c r : Nat) : Region :=
  if inMask m c r then .inside else if inAny ms c r then .other else .out

theorem region_inside_iff (ms : List ((Nat × Nat) × (Nat × Nat))) (m) (c r : Nat) :
    region ms m c r = .inside ↔ inMask m c r = true := by
  unfold region
  by_cases h : inMask m c r = true <;> by_cases h2 : inAny ms c r = true <;> simp_all

theorem region_out_iff (ms : List ((Nat × Nat) × (Nat × Nat))) (m) (c r : Nat) :
    region ms m c r = .out ↔ inMask m c r = false ∧ inAny ms c r = false := by
  unfold region
  by_cases h : inMask m c r = true <;> by_cases h2 : inAny ms c r = true <;> simp_all

theorem region_other_iff (ms : List ((Nat × Nat) × (Nat × Nat))) (m) (c r : Nat) :
    region ms m c r = .other ↔ inMask m c r = false ∧ inAny ms c r = true := by
  unfold region
  by_cases h : inMask m c r = true <;> by_cases h2 : inAny ms c r = true <;> simp_all

theorem region_out_not_in_any (ms : List ((Nat × Nat) × (Nat × Nat))) (m) (c r : Nat)
    (h : region ms m c r = .out) : ∀ m' ∈ ms, inMask m' c r = false := by
  intro m' hm'
  have h2 := ((region_out_iff ms m c r).1 h).2
  cases hb : inMask m' c r
  · rfl
  · have : inAny ms c r = true := (inAny_iff ms c r).2 ⟨m', hm', hb⟩
    simp_all

def exitOffsets (T n : Nat) : List Nat :=
  [T, T + 1, T + n / 4, T + n / 2, T + n * 19 / 20, T + n * 19 / 20 + 1, T + n - 1, T + n, T + n + 1]

theorem exitOffsets_length (T n : Nat) : (exitOffsets T n).length = 9 := rfl

theorem exitOffsets_first (T n : Nat) : (exitOffsets T n).head? = some T := rfl

theorem exitOffsets_last (T n : Nat) : (exitOffsets T n).getLast? = some (T + n + 1) := rfl

theorem exitOffsets_in_range (T n : Nat) (hn : 1 ≤ n) : ∀ y ∈ exitOffsets T n, T ≤ y ∧ y ≤ T + n + 1 := by
  intro y hy
  simp only [exitOffsets, List.mem_cons, List.not_mem_nil, or_false] at hy
  omega

theorem exitOffsets_sorted (T n : Nat) (hn : 40 ≤ n) : (exitOffsets T n).Pairwise (· ≤ ·) := by
  simp only [exitOffsets, List.pairwise_cons, List.mem_cons, List.not_mem_nil, or_false, forall_eq_or_imp,
    forall_eq, List.Pairwise.nil, and_true, false_implies, implies_true]
  omega

def exitClaim (layer : String) (le600 : Bool) : Option Claim :=
  let mk (ps : List CssProp) : Option Claim := some ⟨ps, false, true, false, false, false, none⟩
  if layer == "hero_copy" then mk (if le600 then [.opacity, .transform] else [.opacity, .transform, .filter])
  else if layer == "hero.cue_cue" then mk (if le600 then [.opacity, .transform, .filter] else [.opacity, .filter])
  else if layer == "hero.orbit_card" || layer == "hero.deck_article" then mk [.opacity, .translate]
  else none

theorem exitClaim_text (layer : String) (le600 : Bool) (c : Claim) (h : exitClaim layer le600 = some c) :
    c.text = true := by
  unfold exitClaim at h
  split at h <;> try (simp at h; subst h; rfl)
  split at h <;> try (simp at h; subst h; rfl)
  split at h <;> try (simp at h; subst h; rfl)
  cases h

theorem exitClaim_none (layer : String) (le600 : Bool) (h : exitClaim layer le600 = none) :
    layer ≠ "hero_copy" ∧ layer ≠ "hero.cue_cue" ∧ layer ≠ "hero.orbit_card" ∧ layer ≠ "hero.deck_article" := by
  unfold exitClaim at h
  refine ⟨fun e => ?_, fun e => ?_, fun e => ?_, fun e => ?_⟩ <;> subst e <;> simp at h

/-! ## Accent pin -/

inductive Pin where
  | none | ssr
deriving DecidableEq, Repr

def Pin.name : Pin → String
  | .none => "none" | .ssr => "ssr-accent"

inductive Phase where
  | idle | drawOut | drawIn
deriving DecidableEq, Repr

def Phase.name : Phase → String
  | .idle => "idle" | .drawOut => "draw-out" | .drawIn => "draw-in"

structure Accent where
  cursor : Int
  phase : Phase
deriving DecidableEq, Repr

def Accent.base : Accent := ⟨-1, .idle⟩

def Accent.json (a : Accent) : Json := Json.mkObj [("cursor", toJson a.cursor), ("phase", toJson a.phase.name)]

def pinArms : List String := ["A", "A2", "P"]

def armPin (_arm : String) : Pin := .ssr

def shown (p : Pin) (live : Accent) : Accent := match p with | .none => live | .ssr => Accent.base

def pinAt (arm : String) (_i : Nat) : Pin := armPin arm

def pinMasks (_ : Pin) (ms : List ((Nat × Nat) × (Nat × Nat))) : List ((Nat × Nat) × (Nat × Nat)) := ms

theorem armPin_same (a b : String) : armPin a = armPin b := rfl

theorem armPin_all : ∀ a ∈ pinArms, armPin a = .ssr := fun _ _ => rfl

theorem pinAt_same (a b : String) (i j : Nat) : pinAt a i = pinAt b j := rfl

theorem pinAt_all : ∀ a ∈ pinArms, ∀ i < 9, pinAt a i = .ssr := fun _ _ _ _ => rfl

theorem shown_none (live : Accent) : shown .none live = live := rfl

theorem shown_ssr (live : Accent) : shown .ssr live = Accent.base := rfl

theorem shown_arm_independent (a b : String) (la lb : Accent) : shown (armPin a) la = shown (armPin b) lb := rfl

theorem pinMasks_eq (p : Pin) (ms : List ((Nat × Nat) × (Nat × Nat))) : pinMasks p ms = ms := rfl

theorem region_pin (p : Pin) (ms : List ((Nat × Nat) × (Nat × Nat))) (m : (Nat × Nat) × (Nat × Nat)) (c r : Nat) :
    region (pinMasks p ms) m c r = region ms m c r := rfl

/-! ### The pin per measured row

The pin is applied before each freeze, yet an element can still be re-created between the pin and a shot. A row
records the accent element count and signature at the start and at the end of its two screenshots; a cell may be
graded only when every arm row it uses shows the served accent, once, at both ends. -/

/-- The accent record of one measured arm row: element count, signature at shot start and at shot end. -/
structure AccentRow where
  n : Nat
  start : String
  stop : String
deriving DecidableEq, Repr

/-- One element, and its signature equals the served one at shot start and at shot end. -/
def accentPinned (served start stop : String) (n : Nat) : Bool := n == 1 && start == served && stop == served

def AccentRow.pinned (served : String) (r : AccentRow) : Bool := accentPinned served r.start r.stop r.n

/-- Every arm row a cell uses is pinned. -/
def rowsPinned (served : String) (rows : List AccentRow) : Bool := rows.all (AccentRow.pinned served)

/-- The grade of a cell whose arm rows carry accent records: unpinned rows make it invalid. -/
def gradePinned (served : String) (rows : List AccentRow) (c : Cell) (f : Option Floor) (live : Bool) : Grade :=
  if rowsPinned served rows then gradeRel c f live else .invalid

/-- The reason a cell is invalid because of the accent. -/
def unpinnedWhy (served : String) (rows : List AccentRow) : Option String :=
  if rowsPinned served rows then none else some "accent-unpinned"

/-- The A/A floor of a cell is usable only when the rows behind it are pinned. -/
def floorPinned (served : String) (rows : List AccentRow) (f : Floor) : Floor :=
  { f with valid := f.valid && rowsPinned served rows }

theorem accentPinned_iff (served start stop : String) (n : Nat) :
    accentPinned served start stop n = true ↔ n = 1 ∧ start = served ∧ stop = served := by
  simp [accentPinned, and_assoc]

theorem accentPinned_false_of_n (served start stop : String) (n : Nat) (h : n ≠ 1) :
    accentPinned served start stop n = false := by
  simp [accentPinned, h]

theorem accentPinned_false_of_start (served start stop : String) (n : Nat) (h : start ≠ served) :
    accentPinned served start stop n = false := by
  simp [accentPinned, h]

theorem accentPinned_false_of_stop (served start stop : String) (n : Nat) (h : stop ≠ served) :
    accentPinned served start stop n = false := by
  simp [accentPinned, h]

theorem rowsPinned_iff (served : String) (rows : List AccentRow) :
    rowsPinned served rows = true ↔ ∀ r ∈ rows, accentPinned served r.start r.stop r.n = true := by
  simp [rowsPinned, AccentRow.pinned]

theorem gradePinned_of_pinned (served : String) (rows : List AccentRow) (c : Cell) (f : Option Floor) (live : Bool)
    (h : rowsPinned served rows = true) : gradePinned served rows c f live = gradeRel c f live := by
  simp [gradePinned, h]

theorem gradePinned_invalid_of_unpinned (served : String) (rows : List AccentRow) (c : Cell) (f : Option Floor)
    (live : Bool) (r : AccentRow) (hr : r ∈ rows) (h : accentPinned served r.start r.stop r.n = false) :
    gradePinned served rows c f live = .invalid := by
  have : rowsPinned served rows = false := by
    cases hp : rowsPinned served rows
    · rfl
    · have := (rowsPinned_iff served rows).1 hp r hr; rw [h] at this; cases this
  simp [gradePinned, this]

/-- A cell is valid only if every arm row it uses is pinned. -/
theorem gradePinned_valid_only_if (served : String) (rows : List AccentRow) (c : Cell) (f : Option Floor)
    (live : Bool) (h : gradePinned served rows c f live ≠ .invalid) :
    ∀ r ∈ rows, accentPinned served r.start r.stop r.n = true := by
  intro r hr
  cases hp : accentPinned served r.start r.stop r.n
  · exact absurd (gradePinned_invalid_of_unpinned served rows c f live r hr hp) h
  · rfl

theorem gradePinned_invalid_iff (served : String) (rows : List AccentRow) (c : Cell) (f : Option Floor) (live : Bool) :
    gradePinned served rows c f live = .invalid ↔ rowsPinned served rows = false ∨ live = false ∨ c.valid = false := by
  by_cases h : rowsPinned served rows = true
  · rw [gradePinned_of_pinned served rows c f live h, gradeRel_invalid_iff]; simp [h]
  · have h' : rowsPinned served rows = false := by simpa using h
    simp [gradePinned, h']

theorem unpinnedWhy_iff (served : String) (rows : List AccentRow) :
    (unpinnedWhy served rows).isSome = true ↔ rowsPinned served rows = false := by
  unfold unpinnedWhy
  by_cases h : rowsPinned served rows = true <;> simp [h]

theorem floorPinned_valid_only_if (served : String) (rows : List AccentRow) (f : Floor)
    (h : (floorPinned served rows f).valid = true) : rowsPinned served rows = true := by
  simp [floorPinned] at h; exact h.2

def accentRowCases : List (String × String × String × Nat) :=
  [("22a26c2a", "22a26c2a", "22a26c2a", 1), ("22a26c2a", "e1380ab3", "a7ccf8cf", 1), ("22a26c2a", "e1380ab3", "22a26c2a", 1),
   ("22a26c2a", "22a26c2a", "a7ccf8cf", 1), ("22a26c2a", "22a26c2a", "22a26c2a", 0), ("22a26c2a", "22a26c2a", "22a26c2a", 2)]

def accentRowSets : List (String × List AccentRow) :=
  [("both pinned", [⟨1, "s", "s"⟩, ⟨1, "s", "s"⟩]), ("A unpinned", [⟨1, "x", "y"⟩, ⟨1, "s", "s"⟩]),
   ("B unpinned at the end", [⟨1, "s", "s"⟩, ⟨1, "s", "t"⟩]), ("two elements", [⟨1, "s", "s"⟩, ⟨2, "s", "s"⟩]), ("no rows", [])]

def liveAccentCases : List Accent := [⟨-1, .idle⟩, ⟨2, .drawIn⟩, ⟨5, .drawOut⟩]

def offsetCases : List Nat := [0, 1, 7, 8, 100, 4626, 5000]

def maskCases : List (String × Nat × Nat × Nat × Box) :=
  [("interior box, dpr 3", 3, 1170, 2532, ⟨10000000, 20500000, 100000000, 40000000⟩),
   ("box past the top and left edges", 3, 1170, 2532, ⟨-5000000, -2000000, 50000000, 30000000⟩),
   ("box past the bottom and right edges", 3, 1170, 2532, ⟨380000000, 800000000, 100000000, 100000000⟩),
   ("fractional edges, dpr 3", 3, 1170, 2532, ⟨100000, 333333, 1000000, 1000000⟩),
   ("on the device grid, dpr 2", 2, 780, 1688, ⟨5000000, 5000000, 10000000, 10000000⟩),
   ("empty box", 3, 1170, 2532, ⟨30000000, 30000000, 0, 0⟩),
   ("box fully off screen", 3, 1170, 2532, ⟨0, 900000000, 100000000, 10000000⟩)]

def rawCases : List (List Nat) := [[], [0, 0, 0], [0, 1, 0, 1], [3, 0, 255, 2], [16, 4], [0, 256]]

def goldenLines (_ : Unit := ()) : List String :=
  gradeCases.map (fun (n, c) =>
    (Json.mkObj [("kind", "grade"), ("name", toJson n), ("cell", c.json), ("s1", toJson c.s1),
      ("premises", toJson (c.premises.map Premise.name)), ("grade", toJson (grade c).name)]).compress) ++
  accelCases.map (fun ps =>
    (Json.mkObj [("kind", "accelerated"), ("props", toJson (ps.map cssName)),
      ("accelerated", toJson (accelerated ps))]).compress) ++
  premiseCases.map (fun (n, e, c) =>
    (Json.mkObj [("kind", "premises"), ("name", toJson n), ("engine", toJson e.name), ("claim", c.json),
      ("premises", toJson ((premises e c).map Premise.name))]).compress) ++
  offsetCases.map (fun m =>
    (Json.mkObj [("kind", "offsets"), ("maxY", toJson m), ("offsets", toJson (offsets m))]).compress) ++
  relCases.map (fun (n, c, f, live) =>
    (Json.mkObj [("kind", "rel"), ("name", toJson n), ("cell", c.json),
      ("floor", match f with | some x => x.json | none => Json.null), ("live", toJson live),
      ("grade", toJson (gradeRel c f live).name),
      ("why", match whyL c f live with | some w => toJson w.name | none => Json.null),
      ("ifAccepted", toJson (gradeRel { c with stripsAccepted := true } f live).name)]).compress) ++
  regionCases.map (fun (ms, i, x, y) =>
    let m := ms.getD i ((0, 0), (0, 0))
    (Json.mkObj [("kind", "region"), ("masks", toJson (ms.map fun m => [m.1.1, m.1.2, m.2.1, m.2.2])), ("mine", toJson i),
      ("x", toJson x), ("y", toJson y), ("region", toJson (region ms m x y).name)]).compress) ++
  exitCases.map (fun (t, n) =>
    (Json.mkObj [("kind", "exitOffsets"), ("T", toJson t), ("n", toJson n), ("offsets", toJson (exitOffsets t n))]).compress) ++
  exitClaimCases.map (fun (l, b) =>
    (Json.mkObj [("kind", "exitClaim"), ("layer", toJson l), ("le600", toJson b),
      ("claim", match exitClaim l b with | some c => c.json | none => Json.null)]).compress) ++
  pinArms.flatMap (fun arm => liveAccentCases.map (fun live =>
    (Json.mkObj [("kind", "accentPin"), ("arm", toJson arm), ("pin", toJson (armPin arm).name), ("perOffset", toJson ((List.range 9).map fun i => (pinAt arm i).name)),
      ("live", live.json),
      ("shown", (shown (armPin arm) live).json)]).compress)) ++
  accentRowCases.map (fun (served, start, stop, n) =>
    (Json.mkObj [("kind", "accentRow"), ("served", toJson served), ("start", toJson start), ("stop", toJson stop), ("n", toJson n),
      ("pinned", toJson (accentPinned served start stop n))]).compress) ++
  accentRowSets.flatMap (fun (name, rows) => relCases.map (fun (cn, c, f, live) =>
    (Json.mkObj [("kind", "accentGrade"), ("name", toJson (name ++ ": " ++ cn)), ("served", toJson "s"),
      ("rows", toJson (rows.map fun r => Json.mkObj [("n", toJson r.n), ("start", toJson r.start), ("stop", toJson r.stop)])),
      ("cell", c.json), ("floor", match f with | some x => x.json | none => Json.null),
      ("floorPinned", match f with | some x => (floorPinned "s" rows x).json | none => Json.null), ("live", toJson live),
      ("pinned", toJson (rowsPinned "s" rows)),
      ("why", match unpinnedWhy "s" rows with | some w => toJson w | none => Json.null),
      ("grade", toJson (gradePinned "s" rows c f live).name)]).compress)) ++
  regionCases.map (fun (ms, i, x, y) =>
    let m := ms.getD i ((0, 0), (0, 0))
    (Json.mkObj [("kind", "pinRegion"), ("pin", toJson (armPin "P").name),
      ("masks", toJson ((pinMasks (armPin "P") ms).map fun m => [m.1.1, m.1.2, m.2.1, m.2.2])), ("mine", toJson i),
      ("x", toJson x), ("y", toJson y), ("region", toJson (region (pinMasks (armPin "P") ms) m x y).name)]).compress) ++
  maskCases.map (fun (n, dpr, fw, fh, b) =>
    let m := mask dpr fw fh b
    (Json.mkObj [("kind", "mask"), ("name", toJson n), ("dpr", toJson dpr), ("fw", toJson fw), ("fh", toJson fh),
      ("box", toJson [b.x, b.y, (b.w : Int), (b.h : Int)]),
      ("mask", toJson [m.1.1, m.1.2, m.2.1, m.2.2])]).compress) ++
  rawCases.map (fun px =>
    let r := rawOf px
    (Json.mkObj [("kind", "raw"), ("pixels", toJson px), ("raw", r.json), ("ok", toJson r.ok)]).compress)

def goldenText (_ : Unit := ()) : String := String.intercalate "" ((goldenLines ()).map (· ++ "\n"))

def run (args : List String) : IO UInt32 := do
  match args with
  | ["--check", path] =>
    let cur ← IO.FS.readBinFile path
    if cur.data == (goldenText ()).toUTF8.data then
      IO.eprintln s!"path-pix golden: {path} is up to date ({(goldenLines ()).length} lines)"
      return 0
    IO.eprintln s!"path-pix golden: {path} differs from the generated bytes"
    return 1
  | [] =>
    IO.print (goldenText ())
    return 0
  | _ =>
    IO.eprintln "usage: PathPixGolden [--check <file>]"
    return 2

#guard (gradeCases.map fun (_, c) => (grade c).name) ==
  ["E", "Q", "E1", "E1", "Q", "Q", "L", "L", "L", "L", "invalid", "invalid", "invalid", "invalid", "invalid",
   "invalid", "invalid", "invalid", "invalid", "E", "Q", "Q", "L", "Q", "E", "Q", "E", "Q", "E", "Q", "Q"]
#guard (premiseCases.map fun (_, e, c) => (premises e c).map Premise.name) ==
  [["P1", "P2", "P3", "P4"], ["P2", "P3", "P4"], ["P1", "P2", "P3", "P4", "C5"], ["P1", "P2", "P3", "P4", "S1", "T1"],
   ["P1", "P2", "P3", "P4", "C1", "C5"], ["P1", "P2", "P3", "P4", "S1", "T1"],
   ["P1", "P2", "P3", "P4", "S1", "T1", "C1", "C2"], ["P1", "P2", "P3", "P4", "C6"], ["P1", "P2", "P3", "P4"],
   ["P2", "P3", "P4"], ["P1", "P2", "P3", "P4", "C2"]]
#guard (offsets 4626) == [0, 578, 1156, 1734, 2313, 2891, 3469, 4047, 4626]
#guard (exitOffsets 0 600) == [0, 1, 150, 300, 570, 571, 599, 600, 601]
#guard (relCases.map fun (_, c, f, live) => (gradeRel c f live).name) ==
  ["E", "Q", "L", "L", "L", "L", "L", "Q", "L", "Q", "invalid", "invalid", "L"]
#guard (mask 3 1170 2532 ⟨10000000, 20500000, 100000000, 40000000⟩) == ((29, 331), (60, 183))
#guard (rawOf [3, 0, 255, 2]) == ⟨3, 255⟩ && (rawOf [0, 256]).ok == false
#guard (accelCases.map accelerated) ==
  [true, true, true, true, false, false, false, false, false, false, false, false]

#guard (pinArms.map fun a => (armPin a).name) == ["ssr-accent", "ssr-accent", "ssr-accent"]
#guard (liveAccentCases.map fun l => (shown .ssr l).cursor) == [-1, -1, -1]
#guard (accentRowCases.map fun (a, b, c, n) => accentPinned a b c n) == [true, false, false, false, false, false]
#guard (accentRowSets.map fun (_, rows) => rowsPinned "s" rows) == [true, false, false, false, true]

end Fw.Gate.PathPix
