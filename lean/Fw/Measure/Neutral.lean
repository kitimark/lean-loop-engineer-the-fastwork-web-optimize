import Fw.Measure.Splits
/-!
# N0 windows and the SPK-q verdict on N0/N1 (PLAN §6.7, task n1-lean)

**N0 window attribution** (`packages/measure-chromium/src/n0.mjs`). The page-side census stamps
each style-sheet event with the virtual time `vt` (ms) of the clock shim. With the recorded frame
times `F = [F_0, …, F_{n-1}]`, the profile start `s`, the frame interval `dt` and the tolerance
`ε = 1/1000` ms, an event is in

* `load` when `vt < s − ε`;
* else `preroll` when `vt ≤ p + ε`, where `p = F_0 − dt` is the last pre-roll frame (`p = s` without
  frames);
* else `after` when `vt > ℓ + ε`, where `ℓ` is the last frame time (`ℓ = s` without frames);
* else frame `i`, the first index with `vt − ε ≤ F_i` (a timer due between two frames fires at the
  start of the next one).

The container has no Lean, so `n0.mjs` keeps its own copy; `pure.test.mjs` checks it against the
`measure.n0Windows` golden vectors (non-decreasing frame times, where its binary search finds the
first such index).

**SPK-q verdict** (PLAN §6.7 N0/N1: "W-rest and W-measure: 0"; V-q: "sheet mutations 0 after
hydration"). Over one counts run: `missing` when the census was off, no frame was recorded, or a frame
lacks one of the N0 keys or gated N1 keys (a zero must be a recorded zero); else `pass` when the
pre-roll and after windows hold no N0 event and every recorded frame reads 0 on every N0 key and every
gated N1 key; else `fail`. The load window is not gated (on arm A it is the reference), and the
SVG-image type is not gated (`Splits.n1Gated`).

Proved: an event in frame `i` has `i < n`, `vt − ε ≤ F_i` and `F_j < vt − ε` for all `j < i`
(`winOf_frame`); without frames no event is in a frame (`winOf_nil`); every event lands in exactly
one window and the window totals add up to the number of events (`n0_conservation`); per frame
`n0.events = n0.cssom + n0.sheetNode` (`frameCounts_sum`); `pass` exactly when the conditions above
hold (`verdict_pass_iff`); the load window and the SVG-image type do not change the verdict
(`verdict_load`, `verdict_svg`).
-/
namespace Fw.Measure.Neutral
open Fw.Measure Fw.Measure.Splits

/-! ## N0 windows -/

/-- The window of an N0 event. -/
inductive Win where
  | load
  | preroll
  | frame (n : Nat)
  | after
deriving Repr, DecidableEq

/-- The time tolerance of the attribution (ms). -/
def eps : Rat := 1 / 1000

/-- The time of the last pre-roll frame: one interval before the first recorded frame, the profile
start without frames.
-/
def lastPreroll (fv : List Rat) (startVt dt : Rat) : Rat :=
  match fv with
  | [] => startVt
  | f :: _ => f - dt

/-- The time of the last recorded frame, the profile start without frames. -/
def lastFrame (fv : List Rat) (startVt : Rat) : Rat := fv.getLast?.getD startVt

/-- The first frame index whose time is at least `vt − ε` (`|F|` when there is none). -/
def firstAtOrAfter (fv : List Rat) (vt : Rat) : Nat := fv.findIdx fun f => decide (vt - eps ≤ f)

/-- **The window of an event** at virtual time `vt`. -/
def winOf (fv : List Rat) (startVt dt vt : Rat) : Win :=
  if vt < startVt - eps then .load
  else if vt ≤ lastPreroll fv startVt dt + eps then .preroll
  else if lastFrame fv startVt + eps < vt then .after
  else .frame (firstAtOrAfter fv vt)

/-- One N0 census event: its kind and virtual time. -/
structure N0Event where
  kind : String
  vt : Rat
deriving Repr, DecidableEq

/-- The N0 count types, in the order of `n0.mjs` `N0_KEYS`. -/
def n0Keys : List String := ["n0.events", "n0.cssom", "n0.sheetNode"]

/-- An event kind is a CSSOM write when it starts with `cssom.` or is `adoptedStyleSheets`; any other
kind is a sheet-node change.
-/
def isCssom (kind : String) : Bool := kind.startsWith "cssom." || kind == "adoptedStyleSheets"

/-- The N0 counts of one frame's events. -/
def frameCounts (es : List N0Event) : Counts :=
  [("n0.events", (es.length : Int)), ("n0.cssom", ((es.filter (isCssom ·.kind)).length : Int)),
   ("n0.sheetNode", ((es.filter fun e => !isCssom e.kind).length : Int))]

/-- The events of window `w`. -/
def eventsIn (fv : List Rat) (startVt dt : Rat) (w : Win) (es : List N0Event) : List N0Event :=
  es.filter fun e => winOf fv startVt dt e.vt == w

/-- The events of each recorded frame. -/
def perFrame (fv : List Rat) (startVt dt : Rat) (es : List N0Event) : List (List N0Event) :=
  (List.range fv.length).map fun i => eventsIn fv startVt dt (.frame i) es

-- the case of pure.test.mjs: dt 10, frames 20100, 20110, 20120 (last pre-roll frame 20090)
#guard [5, 20050, 20090, 20095, 20110, 20111, 20999].map (winOf [20100, 20110, 20120] 20000 10) ==
  [.load, .preroll, .preroll, .frame 0, .frame 1, .frame 2, .after]
#guard winOf [20100, 20110] 20000 10 (20100 + 1 / 2000) == .frame 0
#guard winOf [] 20000 10 20000 == .preroll && winOf [] 20000 10 20001 == .after
#guard frameCounts [⟨"cssom.keyframes", 0⟩, ⟨"adoptedStyleSheets", 0⟩, ⟨"sheetNode.added", 0⟩] ==
  [("n0.events", 3), ("n0.cssom", 2), ("n0.sheetNode", 1)]

/-! ## The SPK-q verdict -/

/-- The event totals of the N0 windows outside the recorded frames. -/
structure N0Win where
  load : Nat
  preroll : Nat
  after : Nat
deriving Repr, DecidableEq

/-- The verdict of the styling-neutrality baseline on one run. -/
inductive Verdict where
  | pass
  | fail
  | missing
deriving Repr, DecidableEq

/-- The keys every recorded frame must carry: the N0 keys and the gated N1 keys. -/
def required : List String := n0Keys ++ n1Gated

/-- A key is recorded in a frame's counts (with any value, 0 included). -/
def recorded (C : Counts) (k : String) : Bool := C.any (·.1 == k)

/-- The indices (from `i`) of the frames that satisfy `p`. -/
def idxFrom (p : Counts → Bool) : Nat → List Counts → List Nat
  | _, [] => []
  | i, f :: fs => if p f then i :: idxFrom p (i + 1) fs else idxFrom p (i + 1) fs

/-- The frames that lack a required key. -/
def unrecorded (frames : List Counts) : List Nat :=
  idxFrom (fun C => required.any fun k => !recorded C k) 0 frames

/-- The frames where one of the keys `K` is not 0. -/
def nonzero (keys : List String) (frames : List Counts) : List Nat :=
  idxFrom (fun C => keys.any fun k => countIn C k != 0) 0 frames

/-- **The SPK-q verdict** of one run: N0 windows (`none` when the census was off) and the counts
of the recorded frames.
-/
def verdict (w : Option N0Win) (frames : List Counts) : Verdict :=
  match w with
  | none => .missing
  | some v =>
    if frames.isEmpty || !(unrecorded frames).isEmpty then .missing
    else if v.preroll == 0 && v.after == 0 && (nonzero n0Keys frames).isEmpty &&
        (nonzero n1Gated frames).isEmpty then .pass
    else .fail

/-- A frame with every required key at 0. -/
private def zeroFrame : Counts := (required.map fun k => (k, (0 : Int))) ++ [(svgKey, 17)]

#guard verdict (some ⟨7, 0, 0⟩) [zeroFrame, zeroFrame] == .pass
#guard verdict (some ⟨7, 1, 0⟩) [zeroFrame] == .fail
#guard verdict (some ⟨7, 0, 0⟩) [zeroFrame, ("trace.N1.updateActiveStyleSheets", 1) :: zeroFrame] == .fail
#guard verdict (some ⟨7, 0, 0⟩) [zeroFrame, [("n0.events", 0)]] == .missing
#guard verdict none [zeroFrame] == .missing && verdict (some ⟨0, 0, 0⟩) [] == .missing
#guard unrecorded [zeroFrame, [], zeroFrame, [("n0.events", 0)]] == [1, 3]
#guard nonzero n0Keys [zeroFrame, ("n0.cssom", 2) :: zeroFrame] == [1]

/-! ## Proofs: windows -/

/-- The first index whose time is at least `vt − ε` exists when the last frame time is. -/
theorem firstAtOrAfter_lt {fv : List Rat} {startVt vt : Rat} (hne : fv ≠ [])
    (h : vt - eps ≤ lastFrame fv startVt) : firstAtOrAfter fv vt < fv.length := by
  unfold firstAtOrAfter
  apply List.findIdx_lt_length_of_exists
  obtain ⟨x, hx⟩ := List.getLast?_isSome.mpr hne |> Option.isSome_iff_exists.mp
  refine ⟨x, List.mem_of_getLast? hx, ?_⟩
  simp only [lastFrame, hx, Option.getD_some] at h
  simpa using h

/-- **Frame attribution.** An event in frame `i` lies after the pre-roll and at most `ε` past the
last frame; `i` is a frame index, frame `i` is at or after `vt − ε`, and every earlier frame is
before it.
-/
theorem winOf_frame {fv : List Rat} {startVt dt vt : Rat} {i : Nat}
    (h : winOf fv startVt dt vt = .frame i) :
    ∃ hi : i < fv.length, vt - eps ≤ fv[i] ∧ (∀ j (hj : j < i), fv[j]'(by omega) < vt - eps) ∧
      startVt - eps ≤ vt ∧ lastPreroll fv startVt dt + eps < vt ∧ vt ≤ lastFrame fv startVt + eps := by
  unfold winOf at h
  by_cases h1 : vt < startVt - eps
  · simp [h1] at h
  by_cases h2 : vt ≤ lastPreroll fv startVt dt + eps
  · simp [h1, h2] at h
  by_cases h3 : lastFrame fv startVt + eps < vt
  · simp [h1, h2, h3] at h
  simp only [h1, h2, h3, ite_false, Win.frame.injEq] at h
  subst h
  have hne : fv ≠ [] := by
    intro he
    subst he
    simp only [lastPreroll, lastFrame, List.getLast?_nil, Option.getD_none] at h2 h3
    exact h2 (by grind)
  have hl : vt - eps ≤ lastFrame fv startVt := by grind
  have hlt := firstAtOrAfter_lt (startVt := startVt) hne hl
  refine ⟨hlt, ?_, ?_, by grind, by grind, by grind⟩
  · exact of_decide_eq_true (List.findIdx_getElem (w := hlt))
  · intro j hj
    have := List.not_of_lt_findIdx hj
    simpa [Rat.not_le] using this

/-- Without recorded frames no event is attributed to a frame. -/
theorem winOf_nil (startVt dt vt : Rat) (i : Nat) : winOf [] startVt dt vt ≠ .frame i := by
  intro h
  obtain ⟨hi, _⟩ := winOf_frame h
  simp at hi

/-- An event is in the load window exactly when it is more than `ε` before the profile start. -/
theorem winOf_load_iff (fv : List Rat) (startVt dt vt : Rat) :
    winOf fv startVt dt vt = .load ↔ vt < startVt - eps := by
  unfold winOf
  by_cases h1 : vt < startVt - eps
  · simp [h1]
  · simp only [h1, ite_false, iff_false]
    by_cases h2 : vt ≤ lastPreroll fv startVt dt + eps
    · simp [h2]
    · by_cases h3 : lastFrame fv startVt + eps < vt
      · simp [h2, h3]
      · simp [h2, h3]

/-- Per frame, the events are the CSSOM writes plus the sheet-node changes. -/
theorem frameCounts_sum (E : List N0Event) :
    countIn (frameCounts E) "n0.events" =
      countIn (frameCounts E) "n0.cssom" + countIn (frameCounts E) "n0.sheetNode" := by
  have h : ∀ l : List N0Event,
      l.length = (l.filter (isCssom ·.kind)).length + (l.filter fun e => !isCssom e.kind).length := by
    intro l
    induction l with
    | nil => rfl
    | cons x xs ih => cases hx : isCssom x.kind <;> simp [hx] <;> omega
  simp only [frameCounts, countIn]
  simp
  have := h E
  omega

/-- The number of frame indices below `n` that equal a window: 1 for a frame below `n`, else 0. -/
theorem count_frame_range (w : Win) (n : Nat) :
    ((List.range n).filter fun i => w == .frame i).length =
      match w with
      | .frame i => if i < n then 1 else 0
      | _ => 0 := by
  induction n with
  | zero => cases w <;> simp
  | succ n ih =>
    rw [List.range_succ, List.filter_append, List.length_append, ih]
    cases w with
    | frame i =>
      by_cases hi : i = n
      · subst hi; simp
      · by_cases hlt : i < n
        · simp [hlt, show i < n + 1 by omega, hi]
        · simp [hlt, show ¬ i < n + 1 by omega, hi]
    | _ => simp

/-- **N0 conservation.** Every event lands in exactly one window: the load, pre-roll and after
totals and the per-frame totals add up to the number of events.
-/
theorem n0_conservation (fv : List Rat) (startVt dt : Rat) (es : List N0Event) :
    (eventsIn fv startVt dt .load es).length + (eventsIn fv startVt dt .preroll es).length +
      (eventsIn fv startVt dt .after es).length +
      ((perFrame fv startVt dt es).map List.length).sum = es.length := by
  induction es with
  | nil =>
    simp only [eventsIn, perFrame, List.filter_nil, List.length_nil, List.map_map]
    generalize List.range fv.length = l
    induction l with
    | nil => rfl
    | cons j l ihl => simpa using ihl
  | cons e es ih =>
    have hsum : ((perFrame fv startVt dt (e :: es)).map List.length).sum =
        ((perFrame fv startVt dt es).map List.length).sum +
          ((List.range fv.length).filter fun i => winOf fv startVt dt e.vt == .frame i).length := by
      simp only [perFrame, eventsIn, List.map_map]
      generalize List.range fv.length = l
      induction l with
      | nil => simp
      | cons j l ihl =>
        simp only [List.map_cons, List.sum_cons, List.filter_cons, Function.comp_apply] at ihl ⊢
        rw [ihl]
        by_cases hj : (winOf fv startVt dt e.vt == Win.frame j) = true
        · simp [hj]; omega
        · simp [hj]; omega
    rw [hsum, count_frame_range]
    simp only [eventsIn, List.filter_cons, List.length_cons] at ih ⊢
    cases hc : winOf fv startVt dt e.vt with
    | load => simp; omega
    | preroll => simp; omega
    | after => simp; omega
    | frame i =>
      obtain ⟨hi, _⟩ := winOf_frame hc
      simp [hi]; omega

/-! ## Proofs: the verdict -/

/-- No index is listed exactly when no frame satisfies the predicate. -/
theorem idxFrom_eq_nil (p : Counts → Bool) : ∀ (i : Nat) (fs : List Counts),
    idxFrom p i fs = [] ↔ ∀ f ∈ fs, p f = false
  | _, [] => by simp [idxFrom]
  | i, f :: fs => by
    by_cases hf : p f = true
    · simp [idxFrom, hf]
    · simp [idxFrom, hf, idxFrom_eq_nil p (i + 1) fs]

/-- Two lists are related pointwise by `r`: same length, and `r` holds at every position. -/
inductive Pointwise {α β : Type} (r : α → β → Prop) : List α → List β → Prop
  | nil : Pointwise r [] []
  | cons {a b as bs} : r a b → Pointwise r as bs → Pointwise r (a :: as) (b :: bs)

/-- A pointwise relation carries over to any weaker relation. -/
theorem Pointwise.imp {α β : Type} {r s : α → β → Prop} (hrs : ∀ {a b}, r a b → s a b) :
    ∀ {l : List α} {m : List β}, Pointwise r l m → Pointwise s l m
  | _, _, .nil => .nil
  | _, _, .cons h hs => .cons (hrs h) (Pointwise.imp hrs hs)

/-- Two frame lists whose frames agree on a predicate list the same indices. -/
theorem idxFrom_congr (p : Counts → Bool) : ∀ (i : Nat) {fs gs : List Counts},
    Pointwise (fun f g => p f = p g) fs gs → idxFrom p i fs = idxFrom p i gs
  | _, [], [], .nil => rfl
  | i, _ :: _, _ :: _, .cons h hs => by
    simp only [idxFrom, h, idxFrom_congr p (i + 1) hs]

/-- `any` over a list depends only on the predicate's values at the list's members. -/
theorem any_congr_mem {α : Type} {p q : α → Bool} : ∀ {l : List α}, (∀ x ∈ l, p x = q x) → l.any p = l.any q
  | [], _ => rfl
  | x :: xs, h => by
    simp only [List.any_cons, h x (by simp), any_congr_mem (l := xs) fun y hy => h y (by simp [hy])]

/-- No frame lacks a required key exactly when every frame records every required key. -/
theorem unrecorded_eq_nil (frames : List Counts) :
    unrecorded frames = [] ↔ ∀ f ∈ frames, ∀ k ∈ required, recorded f k = true := by
  rw [unrecorded, idxFrom_eq_nil]
  simp [List.any_eq_false]

/-- No frame has a non-zero key of `K` exactly when every frame reads 0 on every key of `K`. -/
theorem nonzero_eq_nil (keys : List String) (frames : List Counts) :
    nonzero keys frames = [] ↔ ∀ f ∈ frames, ∀ k ∈ keys, countIn f k = 0 := by
  rw [nonzero, idxFrom_eq_nil]
  simp [List.any_eq_false]

/-- **The pass condition.** The verdict is `pass` exactly when the census was on, some frame was
recorded, the pre-roll and after windows are empty, and every recorded frame carries every required
key with value 0.
-/
theorem verdict_pass_iff (w : Option N0Win) (frames : List Counts) :
    verdict w frames = .pass ↔ ∃ v, w = some v ∧ frames ≠ [] ∧ v.preroll = 0 ∧ v.after = 0 ∧
      ∀ f ∈ frames, ∀ k ∈ required, recorded f k = true ∧ countIn f k = 0 := by
  cases w with
  | none => simp [verdict]
  | some v =>
    have hsplit : (∀ f ∈ frames, ∀ k ∈ required, recorded f k = true ∧ countIn f k = 0) ↔
        (∀ f ∈ frames, ∀ k ∈ required, recorded f k = true) ∧
        (∀ f ∈ frames, ∀ k ∈ n0Keys, countIn f k = 0) ∧ (∀ f ∈ frames, ∀ k ∈ n1Gated, countIn f k = 0) := by
      constructor
      · intro h
        exact ⟨fun f hf k hk => (h f hf k hk).1,
          fun f hf k hk => (h f hf k (List.mem_append_left _ hk)).2,
          fun f hf k hk => (h f hf k (List.mem_append_right _ hk)).2⟩
      · rintro ⟨h1, h2, h3⟩ f hf k hk
        refine ⟨h1 f hf k hk, ?_⟩
        rcases List.mem_append.mp hk with hk | hk
        · exact h2 f hf k hk
        · exact h3 f hf k hk
    rw [hsplit, ← unrecorded_eq_nil, ← nonzero_eq_nil, ← nonzero_eq_nil]
    unfold verdict
    by_cases hf : frames = []
    · simp [hf]
    by_cases hu : unrecorded frames = []
    · by_cases hp : v.preroll = 0 <;> by_cases ha : v.after = 0 <;>
        by_cases h0 : nonzero n0Keys frames = [] <;> by_cases h1 : nonzero n1Gated frames = [] <;>
        simp [hf, hu, hp, ha, h0, h1]
    · simp [hf, hu]

/-- **The load window is not gated.** Changing the load total does not change the verdict. -/
theorem verdict_load (v : N0Win) (x : Nat) (frames : List Counts) :
    verdict (some { v with load := x }) frames = verdict (some v) frames := rfl

/-- **The SVG-image type is not gated.** Two runs whose frames agree on every key other than the
SVG-image type (value and whether it is recorded) get the same verdict.
-/
theorem verdict_svg (w : Option N0Win) {fs gs : List Counts}
    (h : Pointwise (fun f g => ∀ k, k ≠ svgKey → recorded f k = recorded g k ∧ countIn f k = countIn g k)
      fs gs) : verdict w fs = verdict w gs := by
  have hreq : ∀ k ∈ required, k ≠ svgKey := by
    intro k hk he
    subst he
    simp [required, n0Keys, svgKey] at hk
    exact svg_not_gated hk
  have hn0 : ∀ k ∈ n0Keys, k ∈ required := fun k hk => List.mem_append_left _ hk
  have hn1 : ∀ k ∈ n1Gated, k ∈ required := fun k hk => List.mem_append_right _ hk
  have cu : unrecorded fs = unrecorded gs := by
    apply idxFrom_congr
    exact Pointwise.imp (fun hfg => any_congr_mem fun k hk => by rw [(hfg k (hreq k hk)).1]) h
  have cz : ∀ keys : List String, (∀ k ∈ keys, k ∈ required) → nonzero keys fs = nonzero keys gs := by
    intro keys hk
    apply idxFrom_congr
    exact Pointwise.imp (fun hfg => any_congr_mem fun k hkk => by rw [(hfg k (hreq k (hk k hkk))).2]) h
  have hl : fs.isEmpty = gs.isEmpty := by
    cases h <;> rfl
  simp only [verdict, hl, cu, cz n0Keys hn0, cz n1Gated hn1]

end Fw.Measure.Neutral
