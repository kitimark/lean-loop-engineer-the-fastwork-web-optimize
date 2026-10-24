import Lean.Data.Json
/-!
# Which painted rects the user cannot see
Proof note: research/notes/2026/10-2x-invisible-paint.md.
-/
namespace Fw.Engine.PaintVisible

/-! ## Rects -/

/-- An integer-pixel rect: top-left corner and size. -/
structure Rect where
  x : Int
  y : Int
  w : Nat
  h : Nat
  deriving Repr, DecidableEq

/-- Pixels in the rect. -/
def Rect.area (r : Rect) : Nat := r.w * r.h

/-- The overlap of two rects; zero-sized when they do not meet. -/
def Rect.inter (a b : Rect) : Rect :=
  { x := max a.x b.x, y := max a.y b.y,
    w := (min (a.x + a.w) (b.x + b.w) - max a.x b.x).toNat,
    h := (min (a.y + a.h) (b.y + b.h) - max a.y b.y).toNat }

/-- `c` holds all of `v`. -/
def Rect.Sub (v c : Rect) : Prop :=
  c.x ≤ v.x ∧ v.x + v.w ≤ c.x + c.w ∧ c.y ≤ v.y ∧ v.y + v.h ≤ c.y + c.h

theorem inter_w_le (a b : Rect) : (a.inter b).w ≤ a.w := by simp only [Rect.inter]; omega
theorem inter_h_le (a b : Rect) : (a.inter b).h ≤ a.h := by simp only [Rect.inter]; omega

theorem inter_area_le (a b : Rect) : (a.inter b).area ≤ a.area :=
  Nat.mul_le_mul (inter_w_le a b) (inter_h_le a b)

theorem inter_area_mono (r v c : Rect) (h : v.Sub c) : (r.inter v).area ≤ (r.inter c).area := by
  obtain ⟨h1, h2, h3, h4⟩ := h
  apply Nat.mul_le_mul <;> simp only [Rect.inter] <;> omega

/-- Split every `if` of the goal. -/
macro "splitAll" : tactic => `(tactic| repeat' split)

/-! ## The classes -/

/-- Pixel evidence for one rect: not compared, equal before and after, or different. -/
inductive Pix | unknown | same | changed
  deriving DecidableEq, Repr

/-- Everything known about one painted rect (all rects in one space, the viewport's). -/
structure Fact where
  rect : Rect
  visible : Rect
  coverage : Rect
  hidden : Bool
  covered : Bool
  clipped : Bool
  pix : Pix

/-- Why a paint is or is not seen, in the order the rule asks. -/
inductive Class | zeroArea | hidden | clippedOut | covered | beyondMargin | prepaintMargin | noop | visible
  deriving DecidableEq, Repr

/-- Every class, in report order. -/
def classes : List Class :=
  [.zeroArea, .hidden, .clippedOut, .covered, .beyondMargin, .prepaintMargin, .noop, .visible]

/-- The name written in reports and the golden. -/
def Class.name : Class → String
  | .zeroArea => "zero-area" | .hidden => "hidden" | .clippedOut => "clipped-out" | .covered => "covered"
  | .beyondMargin => "beyond-margin" | .prepaintMargin => "prepaint-margin" | .noop => "noop" | .visible => "visible"

/-- The class of one painted rect. -/
def classify (f : Fact) : Class :=
  if f.rect.area = 0 then .zeroArea
  else if f.hidden then .hidden
  else if f.clipped then .clippedOut
  else if f.covered then .covered
  else if 0 < (f.rect.inter f.visible).area then (if f.pix = .same then .noop else .visible)
  else if 0 < (f.rect.inter f.coverage).area then .prepaintMargin
  else .beyondMargin

theorem zeroArea_iff (f : Fact) : classify f = .zeroArea ↔ f.rect.area = 0 := by
  unfold classify; splitAll <;> simp_all

theorem hidden_iff (f : Fact) : classify f = .hidden ↔ f.rect.area ≠ 0 ∧ f.hidden = true := by
  unfold classify; splitAll <;> simp_all

theorem clippedOut_iff (f : Fact) :
    classify f = .clippedOut ↔ f.rect.area ≠ 0 ∧ f.hidden = false ∧ f.clipped = true := by
  unfold classify; splitAll <;> simp_all

theorem covered_iff (f : Fact) :
    classify f = .covered ↔ f.rect.area ≠ 0 ∧ f.hidden = false ∧ f.clipped = false ∧ f.covered = true := by
  unfold classify; splitAll <;> simp_all

/-- Rects that reach the screen at all: not empty, shown, not clipped away, not under an opaque layer. -/
def Reaches (f : Fact) : Prop :=
  f.rect.area ≠ 0 ∧ f.hidden = false ∧ f.clipped = false ∧ f.covered = false

theorem beyondMargin_iff (f : Fact) :
    classify f = .beyondMargin ↔
      Reaches f ∧ (f.rect.inter f.visible).area = 0 ∧ (f.rect.inter f.coverage).area = 0 := by
  unfold classify Reaches; splitAll <;> simp_all <;> omega

theorem prepaintMargin_iff (f : Fact) :
    classify f = .prepaintMargin ↔
      Reaches f ∧ (f.rect.inter f.visible).area = 0 ∧ 0 < (f.rect.inter f.coverage).area := by
  unfold classify Reaches; splitAll <;> simp_all <;> omega

theorem noop_iff (f : Fact) :
    classify f = .noop ↔ Reaches f ∧ 0 < (f.rect.inter f.visible).area ∧ f.pix = .same := by
  unfold classify Reaches; splitAll <;> simp_all

theorem visible_iff (f : Fact) :
    classify f = .visible ↔ Reaches f ∧ 0 < (f.rect.inter f.visible).area ∧ f.pix ≠ .same := by
  unfold classify Reaches; splitAll <;> simp_all

/-- A rect with no pixel evidence is never called a no-op. -/
theorem not_noop_of_unknown (f : Fact) (h : f.pix = .unknown) : classify f ≠ .noop := by
  rw [Ne, noop_iff]; simp [h]

/-! ## Counts and area -/

/-- Pixels of the rect that the user sees: the overlap with the viewport when the paint is `visible`, else none. -/
def seenArea (f : Fact) : Nat := if classify f = .visible then (f.rect.inter f.visible).area else 0

/-- Pixels painted that the user does not see. -/
def wasteArea (f : Fact) : Nat := f.rect.area - seenArea f

theorem seenArea_le (f : Fact) : seenArea f ≤ f.rect.area := by
  unfold seenArea; split
  · exact inter_area_le _ _
  · exact Nat.zero_le _

theorem seen_add_waste (f : Fact) : seenArea f + wasteArea f = f.rect.area := by
  have := seenArea_le f; unfold wasteArea; omega

theorem waste_full_of_ne_visible (f : Fact) (h : classify f ≠ .visible) : wasteArea f = f.rect.area := by
  simp [wasteArea, seenArea, h]

/-- How many rects have class `c`. -/
def tally (fs : List Fact) (c : Class) : Nat := (fs.map classify).count c

theorem tally_sum (fs : List Fact) : (classes.map (tally fs)).sum = fs.length := by
  induction fs with
  | nil => simp [classes, tally]
  | cons f fs ih =>
    have e : ∀ c, tally (f :: fs) c = tally fs c + if classify f = c then 1 else 0 := by
      intro c; simp only [tally, List.map_cons, List.count_cons, beq_iff_eq]
    simp only [classes, List.map_cons, List.map_nil, List.sum_cons, List.sum_nil] at ih ⊢
    simp only [e]
    cases classify f <;> simp <;> omega

/-- Rects per 100 frames, rounded down; none for an empty window. -/
def per100 (total frames : Nat) : Nat := if frames = 0 then 0 else total * 100 / frames

theorem per100_zero (total : Nat) : per100 total 0 = 0 := by simp [per100]

theorem per100_mono (a b frames : Nat) (h : a ≤ b) : per100 a frames ≤ per100 b frames := by
  unfold per100; split
  · exact Nat.le_refl _
  · exact Nat.div_le_div_right (Nat.mul_le_mul_right 100 h)

/-! ## Where the tiles reach -/

/-- The tile margin in layer pixels: 512 over the contents scale (`TileController.cpp` `kDefaultTileSize`). -/
def margin (scale : Nat) : Nat := 512 / scale

/--
The vertical tile coverage of a viewport `v` in a layer `contentH` tall, moving `dir` (positive down), margin `m`:
one margin ahead of the motion, half a margin each side when still, shifted back inside the layer, never above 0.
-/
def coverage (v : Rect) (dir : Int) (m contentH : Nat) : Rect :=
  let h' : Nat := v.h + m
  let y0 : Int := if dir < 0 then v.y - m else if dir = 0 then v.y - (m / 2 : Nat) else v.y
  let y1 : Int := if y0 + h' > contentH then (contentH : Int) - h' else y0
  { x := v.x, y := max y1 0, w := v.w, h := h' }

theorem coverage_sub (v : Rect) (dir : Int) (m contentH : Nat) (h0 : 0 ≤ v.y) (h1 : v.y + v.h ≤ contentH) :
    v.Sub (coverage v dir m contentH) := by
  unfold coverage Rect.Sub
  refine ⟨Int.le_refl _, by simp, ?_, ?_⟩ <;> simp only [] <;> splitAll <;> omega

/-! ## A layer that changes size -/

/-- Pixels re-rastered when a layer's size goes from `old` to `new`: a non-tiled layer that changes size is painted whole. -/
def rerasterArea (tiled : Bool) (old new : Nat × Nat) : Nat :=
  if tiled || old == new then 0 else new.1 * new.2

theorem reraster_tiled (old new : Nat × Nat) : rerasterArea true old new = 0 := by simp [rerasterArea]

theorem reraster_same (t : Bool) (s : Nat × Nat) : rerasterArea t s s = 0 := by simp [rerasterArea]

theorem reraster_resized (old new : Nat × Nat) (h : old ≠ new) : rerasterArea false old new = new.1 * new.2 := by
  simp [rerasterArea, h]

/-! ## The dirty rects of a layer

`GraphicsLayerCA::setNeedsDisplayInRect` records every call in the tracked repaint list, then keeps a rect only when no
kept rect holds it, and merges into the first kept rect once 32 are kept (`GraphicsLayerCA.cpp:1031-1043`@862f17d). The
paints of one frame are the kept list, so the tracked list over-counts by the calls the engine drops.
-/

/-- `c` holds all of `r`. -/
def Rect.holds (c r : Rect) : Bool :=
  decide (c.x ≤ r.x ∧ r.x + r.w ≤ c.x + c.w ∧ c.y ≤ r.y ∧ r.y + r.h ≤ c.y + c.h)

/-- The smallest rect that holds both. -/
def Rect.unite (a b : Rect) : Rect :=
  { x := min a.x b.x, y := min a.y b.y,
    w := (max (a.x + a.w) (b.x + b.w) - min a.x b.x).toNat,
    h := (max (a.y + a.h) (b.y + b.h) - min a.y b.y).toNat }

/-- How many dirty rects a layer keeps (`maxDirtyRects`). -/
def dirtyCap : Nat := 32

/-- One `setNeedsDisplayInRect` call on the kept rects `ds`. -/
def addDirty (ds : List Rect) (r : Rect) : List Rect :=
  if ds.any (·.holds r) then ds
  else if ds.length < dirtyCap then ds ++ [r]
  else match ds with
    | [] => [r]
    | d :: t => d.unite r :: t

/-- The kept rects after the calls `rs`, in order. -/
def dirty (rs : List Rect) : List Rect := rs.foldl addDirty []

theorem addDirty_held (ds : List Rect) (r : Rect) (h : ds.any (·.holds r) = true) : addDirty ds r = ds := by
  simp [addDirty, h]

theorem addDirty_append (ds : List Rect) (r : Rect) (h : ds.any (·.holds r) = false) (hl : ds.length < dirtyCap) :
    addDirty ds r = ds ++ [r] := by
  simp [addDirty, h, hl]

theorem addDirty_merge (d : Rect) (t : List Rect) (r : Rect) (h : (d :: t).any (·.holds r) = false)
    (hl : ¬ (d :: t).length < dirtyCap) : addDirty (d :: t) r = d.unite r :: t := by
  have hl' : ¬ (t.length + 1 < dirtyCap) := hl
  simp [addDirty, h, hl']

theorem addDirty_len (ds : List Rect) (r : Rect) (h : ds.length ≤ dirtyCap) : (addDirty ds r).length ≤ dirtyCap := by
  unfold addDirty
  split
  · exact h
  · split
    · rename_i _ hl
      simp only [List.length_append, List.length_singleton]
      unfold dirtyCap at *
      omega
    · rcases ds with _ | ⟨d, t⟩
      · simp [dirtyCap]
      · simp only [List.length_cons]
        simp only [List.length_cons] at h
        omega

theorem addDirty_len_le (ds : List Rect) (r : Rect) : (addDirty ds r).length ≤ ds.length + 1 := by
  unfold addDirty
  split
  · omega
  · split
    · simp
    · rcases ds with _ | ⟨d, t⟩ <;> simp

private theorem foldl_len (rs ds : List Rect) (h : ds.length ≤ dirtyCap) : (rs.foldl addDirty ds).length ≤ dirtyCap := by
  induction rs generalizing ds with
  | nil => exact h
  | cons r rs ih => exact ih _ (addDirty_len ds r h)

private theorem foldl_len_le (rs ds : List Rect) : (rs.foldl addDirty ds).length ≤ ds.length + rs.length := by
  induction rs generalizing ds with
  | nil => simp
  | cons r rs ih =>
    have := addDirty_len_le ds r
    have := ih (addDirty ds r)
    simp only [List.foldl_cons, List.length_cons]
    omega

/-- A layer keeps at most 32 dirty rects however many calls come. -/
theorem dirty_len_le_cap (rs : List Rect) : (dirty rs).length ≤ dirtyCap := foldl_len rs [] (by simp)

/-- The kept rects are no more than the calls. -/
theorem dirty_len_le (rs : List Rect) : (dirty rs).length ≤ rs.length := by
  have := foldl_len_le rs []
  simpa [dirty] using this

theorem holds_unite_right (a r : Rect) : (a.unite r).holds r = true := by
  unfold Rect.holds
  rw [decide_eq_true_eq]
  simp only [Rect.unite]
  omega

theorem holds_self (r : Rect) : r.holds r = true := by
  simp only [Rect.holds, decide_eq_true_eq]
  omega

/-- After a call, some kept rect holds the rect. -/
theorem addDirty_holds (ds : List Rect) (r : Rect) : (addDirty ds r).any (·.holds r) = true := by
  by_cases h : ds.any (·.holds r) = true
  · rw [addDirty_held ds r h]; exact h
  · have h' : ds.any (·.holds r) = false := by simpa using h
    by_cases hl : ds.length < dirtyCap
    · rw [addDirty_append ds r h' hl]; simp [holds_self]
    · rcases ds with _ | ⟨d, t⟩
      · simp [dirtyCap] at hl
      · rw [addDirty_merge d t r h' hl]; simp [holds_unite_right]

/-- The same call twice in a row keeps the same rects: the engine drops the repeat. -/
theorem addDirty_twice (ds : List Rect) (r : Rect) : addDirty (addDirty ds r) r = addDirty ds r :=
  addDirty_held _ _ (addDirty_holds ds r)

/-! ## Golden lines -/

private def rj (r : Rect) : Lean.Json := .arr #[.num r.x, .num r.y, .num r.w, .num r.h]

private def pixName : Pix → String | .unknown => "unknown" | .same => "same" | .changed => "changed"

private def vp : Rect := ⟨0, 100, 430, 932⟩
private def cov : Rect := ⟨0, 0, 430, 1700⟩

private def mkFact (r : Rect) (hi cv cl : Bool) (p : Pix) : Fact := ⟨r, vp, cov, hi, cv, cl, p⟩

/-- The facts the golden classifies. -/
def sampleFacts : List Fact :=
  [ mkFact ⟨0, 200, 100, 0⟩ false false false .unknown,
    mkFact ⟨0, 200, 100, 50⟩ true false false .changed,
    mkFact ⟨0, 200, 100, 50⟩ false false true .changed,
    mkFact ⟨0, 200, 100, 50⟩ false true false .changed,
    mkFact ⟨0, 1500, 100, 50⟩ false false false .changed,
    mkFact ⟨0, 1900, 100, 50⟩ false false false .changed,
    mkFact ⟨0, 300, 100, 50⟩ false false false .same,
    mkFact ⟨0, 300, 100, 50⟩ false false false .unknown,
    mkFact ⟨0, 300, 100, 50⟩ false false false .changed,
    mkFact ⟨0, 60, 100, 100⟩ false false false .changed,
    mkFact ⟨0, 60, 100, 30⟩ false false false .changed,
    mkFact ⟨0, 1000, 100, 132⟩ false false false .changed,
    mkFact ⟨0, 1032, 430, 100⟩ false false false .changed,
    mkFact ⟨400, 300, 100, 50⟩ false false false .changed ]

#guard ((sampleFacts.map classify).map Class.name) ==
  ["zero-area", "hidden", "clipped-out", "covered", "prepaint-margin", "beyond-margin", "noop", "visible", "visible",
   "visible", "prepaint-margin", "visible", "prepaint-margin", "visible"]
#guard (sampleFacts.map seenArea) == [0, 0, 0, 0, 0, 0, 0, 5000, 5000, 6000, 0, 3200, 0, 1500]
#guard tally sampleFacts .visible == 5
#guard coverage ⟨0, 100, 430, 932⟩ 1 512 4000 == ⟨0, 100, 430, 1444⟩
#guard coverage ⟨0, 100, 430, 932⟩ (-1) 512 4000 == ⟨0, 0, 430, 1444⟩
#guard coverage ⟨0, 1000, 430, 932⟩ 0 512 1700 == ⟨0, 256, 430, 1444⟩
#guard rerasterArea false (430, 60) (430, 80) == 34400
#guard per100 7 3 == 233
#guard (dirty [⟨0, 0, 10, 10⟩, ⟨0, 0, 10, 10⟩, ⟨0, 0, 10, 10⟩]).length == 1
#guard dirty [⟨0, 0, 10, 10⟩, ⟨2, 2, 3, 3⟩] == [⟨0, 0, 10, 10⟩]
#guard dirty [⟨2, 2, 3, 3⟩, ⟨0, 0, 10, 10⟩] == [⟨2, 2, 3, 3⟩, ⟨0, 0, 10, 10⟩]
#guard (dirty ((List.range 40).map fun i => (⟨((2 * i : Nat) : Int), 0, 1, 1⟩ : Rect))).length == 32

private def line (fn : String) (inp : List (String × Lean.Json)) (out : Lean.Json) : String :=
  (Lean.Json.mkObj [("fn", .str fn), ("in", Lean.Json.mkObj inp), ("out", out)]).compress

private def coverageCases : List (Rect × Int × Nat × Nat) :=
  [(⟨0, 100, 430, 932⟩, 1, 3, 4000), (⟨0, 100, 430, 932⟩, -1, 3, 4000), (⟨0, 1000, 430, 932⟩, 0, 3, 1700),
   (⟨0, 768, 430, 932⟩, 1, 2, 1700), (⟨0, 0, 430, 932⟩, -1, 3, 4000), (⟨0, 0, 430, 932⟩, 0, 3, 4000)]

private def dirtyCases : List (List Rect) :=
  [ [], [⟨0, 0, 10, 10⟩, ⟨0, 0, 10, 10⟩, ⟨0, 0, 10, 10⟩], [⟨0, 0, 10, 10⟩, ⟨2, 2, 3, 3⟩], [⟨2, 2, 3, 3⟩, ⟨0, 0, 10, 10⟩],
    [⟨0, 0, 10, 10⟩, ⟨20, 0, 10, 10⟩, ⟨0, 0, 10, 10⟩], [⟨-1, 5, 1, 1⟩, ⟨-1, 5, 1, 1⟩],
    (List.range 34).map fun i => (⟨((2 * i : Nat) : Int), 0, 1, 1⟩ : Rect),
    ((List.range 34).map fun i => (⟨((2 * i : Nat) : Int), 0, 1, 1⟩ : Rect)) ++ [⟨0, 0, 100, 1⟩, ⟨66, 0, 1, 1⟩] ]

/-- The golden lines `packages/contracts/golden/engine/paint-visible.jsonl`. -/
def lines : List String :=
  sampleFacts.map (fun f =>
    line "classify"
      [("rect", rj f.rect), ("visible", rj f.visible), ("coverage", rj f.coverage), ("hidden", .bool f.hidden),
       ("covered", .bool f.covered), ("clipped", .bool f.clipped), ("pix", .str (pixName f.pix))]
      (Lean.Json.mkObj [("class", .str (classify f).name), ("seen", .num (seenArea f)), ("waste", .num (wasteArea f))])) ++
  [ line "tally" [("classes", .arr (sampleFacts.map (fun f => Lean.Json.str (classify f).name)).toArray)]
      (Lean.Json.mkObj (classes.map fun c => (c.name, Lean.Json.num (tally sampleFacts c)))) ] ++
  coverageCases.map (fun (v, d, sc, ch) =>
    line "coverage" [("visible", rj v), ("dir", .num d), ("scale", .num sc), ("contentH", .num ch)]
      (rj (coverage v d (margin sc) ch))) ++
  ([((430, 60), (430, 80), false), ((430, 60), (430, 80), true), ((430, 60), (430, 60), false), ((0, 0), (430, 60), false)] : List ((Nat × Nat) × (Nat × Nat) × Bool)).map
    (fun (o, n, t) =>
      line "rerasterArea"
        [("old", .arr #[.num o.1, .num o.2]), ("new", .arr #[.num n.1, .num n.2]), ("tiled", .bool t)]
        (.num (rerasterArea t o n))) ++
  ([(7, 3), (7, 0), (0, 5), (1234, 650)] : List (Nat × Nat)).map (fun (t, n) =>
    line "per100" [("total", .num t), ("frames", .num n)] (.num (per100 t n))) ++
  dirtyCases.map fun rs =>
    line "dirty" [("calls", .arr (rs.map rj).toArray)] (.arr ((dirty rs).map rj).toArray)

/-- The golden text. -/
def goldenText : String := String.join (lines.map (· ++ "\n"))

/-- Print the golden text, or with `--check <file>` compare it; exit 1 on a difference. -/
def run (args : List String) : IO UInt32 := do
  match args with
  | ["--check", path] =>
    if (← IO.FS.readFile path) == goldenText then
      IO.eprintln s!"paint-visible golden: {path} is up to date ({lines.length} lines)"
      return 0
    IO.eprintln s!"paint-visible golden: {path} differs from the generated text"
    return 1
  | _ =>
    IO.print goldenText
    return 0

end Fw.Engine.PaintVisible
