import Lean.Data.Json
import Fw.Engine.Visual
import Fw.Parts.Bezier
import Fw.Parts.Nav
/-!
# nav, variant `earn-no-transition`: the earn button's CSS transitions are off while the nav is morphing
Proof note: research/notes/2026/10-20-earn-transition-retarget.md.
-/
namespace Fw.Parts.NavEarnOpt

open Fw.Engine Fw.Parts.Bezier

/-! ## The decision -/

/-- Whether the earn button's transitions are listed: off only under the flag while the nav is morphing. -/
def transitionsOn (flag morphing : Bool) : Bool := !(flag && morphing)

#guard transitionsOn false false == true
#guard transitionsOn false true == true
#guard transitionsOn true false == true
#guard transitionsOn true true == false

theorem transitionsOn_faithful (morphing : Bool) : transitionsOn false morphing = true := by
  cases morphing <;> rfl

theorem transitionsOn_flag_rest : transitionsOn true false = true := rfl

theorem transitionsOn_flag_morphing : transitionsOn true true = false := rfl

/-! ## One transitioned property -/

/-- A CSS transition: delay and duration in ms, and its timing curve. -/
structure Tr where
  delay : Rat
  dur : Rat
  curve : Bez
deriving Repr, BEq, DecidableEq

def curve : Bez := ⟨33 / 100, 0, 1 / 5, 1⟩

def maxWTr : Tr := ⟨0, 680, curve⟩

def padTr : Tr := ⟨0, 680, curve⟩

def opacityTr : Tr := ⟨120, 320, curve⟩

/-- The property's running state: start and end value, start time, and whether a transition runs. -/
structure Run where
  fromV : Rat
  toV : Rat
  start : Rat
  live : Bool
deriving Repr, BEq, DecidableEq, Inhabited

def rest (v t : Rat) : Run := ⟨v, v, t, false⟩

def value (tr : Tr) (r : Run) (now : Rat) : Rat :=
  if r.live then r.fromV + (r.toV - r.fromV) * ease tr.curve ((now - r.start - tr.delay) / tr.dur) else r.toV

/-- Frame by frame: `g k` is the computed value at frame `k`, `on k` whether the property is listed in `transition`. -/
def run (tr : Tr) (time g : Nat → Rat) (on : Nat → Bool) : Nat → Run
  | 0 => rest (g 0) (time 0)
  | k + 1 =>
    if on (k + 1) = false then rest (g (k + 1)) (time (k + 1))
    else if g (k + 1) = g k then run tr time g on k
    else ⟨value tr (run tr time g on k) (time (k + 1)), g (k + 1), time (k + 1), true⟩

def shown (tr : Tr) (time g : Nat → Rat) (on : Nat → Bool) (k : Nat) : Rat :=
  value tr (run tr time g on k) (time k)

def faithfulOn : Nat → Bool := fun _ => true

theorem toV_run (tr : Tr) (time g : Nat → Rat) (on : Nat → Bool) (k : Nat) : (run tr time g on k).toV = g k := by
  induction k with
  | zero => rfl
  | succ k ih =>
    simp only [run]
    split
    · rfl
    · split
      · next h => rw [ih, h]
      · rfl

theorem value_rest (tr : Tr) (r : Run) (now : Rat) (h : r.live = false) : value tr r now = r.toV := by
  simp [value, h]

/-- Unlisted, the property shows its computed value at once. -/
theorem shown_off (tr : Tr) (time g : Nat → Rat) (on : Nat → Bool) (k : Nat) (h : on k = false) :
    shown tr time g on k = g k := by
  cases k with
  | zero => rfl
  | succ k => simp [shown, run, h, value, rest]

/-- Listed, a change shows no step at its own frame: the old trajectory's value is shown. -/
theorem shown_retarget (tr : Tr) (time g : Nat → Rat) (on : Nat → Bool) (k : Nat) (hon : on (k + 1) = true)
    (hg : g (k + 1) ≠ g k) (hd : 0 ≤ tr.delay) (hdur : 0 < tr.dur) :
    shown tr time g on (k + 1) = value tr (run tr time g on k) (time (k + 1)) := by
  have h0 : (time (k + 1) - time (k + 1) - tr.delay) / tr.dur ≤ 0 := by
    have : time (k + 1) - time (k + 1) - tr.delay = -tr.delay := by grind
    rw [this, Rat.div_def]
    have hi : 0 < tr.dur⁻¹ := Rat.inv_pos.mpr hdur
    have := Rat.mul_le_mul_of_nonneg_right (show -tr.delay ≤ 0 by grind) (Rat.le_of_lt hi)
    grind
  simp [shown, run, hon, hg, value, ease_nonpos _ _ h0, Rat.add_zero]

/-- From rest, the faithful arm shows the old value at the frame the computed value changes. -/
theorem faithful_lags (tr : Tr) (time g : Nat → Rat) (k : Nat) (hrest : (run tr time g faithfulOn k).live = false)
    (hg : g (k + 1) ≠ g k) (hd : 0 ≤ tr.delay) (hdur : 0 < tr.dur) :
    shown tr time g faithfulOn (k + 1) = g k := by
  rw [shown_retarget tr time g faithfulOn k rfl hg hd hdur, value_rest _ _ _ hrest, toV_run]

theorem start_le (tr : Tr) (time g : Nat → Rat) (on : Nat → Bool) (hmono : ∀ i, time i ≤ time (i + 1)) (k : Nat) :
    (run tr time g on k).start ≤ time k := by
  induction k with
  | zero => simp [run, rest]
  | succ k ih =>
    simp only [run]
    split
    · simp [rest]
    · split
      · exact Rat.le_trans ih (hmono k)
      · exact Rat.le_refl

theorem quiet_inv (tr : Tr) (time g : Nat → Rat) (on : Nat → Bool) (hmono : ∀ i, time i ≤ time (i + 1)) (j : Nat) :
    ∀ n, (∀ i, j < i → i ≤ j + n → g i = g j) →
      (run tr time g on (j + n)).live = false ∨ (run tr time g on (j + n)).start ≤ time j := by
  intro n
  induction n with
  | zero => intro _; exact .inr (start_le tr time g on hmono j)
  | succ n ih =>
    intro hq
    have hq' : ∀ i, j < i → i ≤ j + n → g i = g j := fun i h1 h2 => hq i h1 (by omega)
    have hn1 : g (j + n + 1) = g (j + n) := by
      rw [hq (j + n + 1) (by omega) (by omega)]
      rcases Nat.eq_zero_or_pos n with h | h
      · subst h; rfl
      · exact (hq' (j + n) (by omega) (by omega)).symm
    show (run tr time g on (j + n + 1)).live = false ∨ (run tr time g on (j + n + 1)).start ≤ time j
    simp only [run]
    split
    · exact .inl rfl
    · exact ih hq'

/-- **Settled frames agree.** Once the computed value has been still for the delay plus the duration, every arm shows it. -/
theorem shown_settled (tr : Tr) (time g : Nat → Rat) (on : Nat → Bool) (hmono : ∀ i, time i ≤ time (i + 1))
    (hdur : 0 < tr.dur) (j n : Nat) (hq : ∀ i, j < i → i ≤ j + n → g i = g j)
    (hT : time j + tr.delay + tr.dur ≤ time (j + n)) :
    shown tr time g on (j + n) = g (j + n) := by
  unfold shown
  rcases quiet_inv tr time g on hmono j n hq with h | h
  · rw [value_rest _ _ _ h, toV_run]
  · unfold value
    split
    · have h1 : 1 ≤ (time (j + n) - (run tr time g on (j + n)).start - tr.delay) / tr.dur := by
        have hx : tr.dur ≤ time (j + n) - (run tr time g on (j + n)).start - tr.delay := by grind
        rw [Rat.div_def]
        have hi : 0 < tr.dur⁻¹ := Rat.inv_pos.mpr hdur
        have := Rat.mul_le_mul_of_nonneg_right hx (Rat.le_of_lt hi)
        rw [Rat.mul_inv_cancel _ (Rat.ne_of_gt hdur)] at this
        exact this
      rw [ease_ge_one _ _ h1, toV_run]
      grind
    · rw [toV_run]

/-- A frame where every arm has settled: the computed value has been still for the delay plus the duration. -/
def Settled (tr : Tr) (time g : Nat → Rat) : Type :=
  { p : Nat × Nat // (∀ i, p.1 < i → i ≤ p.1 + p.2 → g i = g p.1) ∧ time p.1 + tr.delay + tr.dur ≤ time (p.1 + p.2) }

theorem settled_same (tr : Tr) (time g : Nat → Rat) (on on' : Nat → Bool) (hmono : ∀ i, time i ≤ time (i + 1))
    (hdur : 0 < tr.dur) (s : Settled tr time g) :
    shown tr time g on (s.1.1 + s.1.2) = shown tr time g on' (s.1.1 + s.1.2) := by
  rw [shown_settled tr time g on hmono hdur _ _ s.2.1 s.2.2, shown_settled tr time g on' hmono hdur _ _ s.2.1 s.2.2]

/-! ## The visual claim -/

/-- **VisSame (E) on settled frames.** Any scene drawn from the shown value is the same in both arms. -/
theorem visSame_settled {Env : Type} (vp : Env → Rect) (draw : Env → Rat → Scene) (tr : Tr) (time g : Nat → Rat)
    (on on' : Nat → Bool) (hmono : ∀ i, time i ≤ time (i + 1)) (hdur : 0 < tr.dur) :
    VisSame E vp (fun env (s : Settled tr time g) => draw env (shown tr time g on (s.1.1 + s.1.2)))
      (fun env s => draw env (shown tr time g on' (s.1.1 + s.1.2))) :=
  visSame_of_eq vp fun env s => by rw [settled_same tr time g on on' hmono hdur s]

/-! ## The work bound -/

def running (tr : Tr) (r : Run) (now : Rat) : Bool := r.live && decide (now < r.start + tr.delay + tr.dur)

/-- The property's style changes at frame `k`: its computed value moved, or a transition is in effect. -/
def dirty (tr : Tr) (time g : Nat → Rat) (on : Nat → Bool) : Nat → Bool
  | 0 => false
  | k + 1 => decide (g (k + 1) ≠ g k) || running tr (run tr time g on (k + 1)) (time (k + 1))

def work (tr : Tr) (time g : Nat → Rat) (on : Nat → Bool) (n : Nat) : Nat :=
  (List.range n).countP (dirty tr time g on ·)

theorem live_inv (tr : Tr) (time g : Nat → Rat) (on : Nat → Bool) (k : Nat) :
    (run tr time g on k).live = true →
      (run tr time g faithfulOn k).live = true ∧ (run tr time g faithfulOn k).start = (run tr time g on k).start := by
  induction k with
  | zero => simp [run, rest]
  | succ k ih =>
    intro h
    simp only [run] at h ⊢
    have hf : faithfulOn (k + 1) = true := rfl
    simp only [hf, Bool.true_eq_false, ↓reduceIte]
    split at h
    · simp [rest] at h
    · split
      · next hg => rw [ite_eq_left_of_eq_true _ _ (eq_true hg)] at h; exact ih h
      · next hg => rw [ite_eq_right_of_eq_false _ _ (eq_false hg)] at h; exact ⟨rfl, rfl⟩

theorem running_le (tr : Tr) (time g : Nat → Rat) (on : Nat → Bool) (k : Nat) :
    running tr (run tr time g on k) (time k) = true → running tr (run tr time g faithfulOn k) (time k) = true := by
  intro h
  simp only [running, Bool.and_eq_true] at h ⊢
  have := live_inv tr time g on k h.1
  exact ⟨this.1, by rw [this.2]; exact h.2⟩

theorem dirty_le (tr : Tr) (time g : Nat → Rat) (on : Nat → Bool) (k : Nat) :
    dirty tr time g on k = true → dirty tr time g faithfulOn k = true := by
  cases k with
  | zero => simp [dirty]
  | succ k =>
    simp only [dirty, Bool.or_eq_true]
    intro h
    rcases h with h | h
    · exact .inl h
    · exact .inr (running_le tr time g on (k + 1) h)

/-- **Work bound.** Over any frame range, any arm changes the property's style on at most the faithful arm's frames. -/
theorem work_le (tr : Tr) (time g : Nat → Rat) (on : Nat → Bool) (n : Nat) :
    work tr time g on n ≤ work tr time g faithfulOn n :=
  List.countP_mono_left fun k _ h => dirty_le tr time g on k h

/-- Unlisted, the property runs no transition. -/
theorem running_off (tr : Tr) (time g : Nat → Rat) (on : Nat → Bool) (k : Nat) (h : on k = false) :
    running tr (run tr time g on k) (time k) = false := by
  cases k with
  | zero => rfl
  | succ k => simp [run, h, running, rest]

/-! ## Linear-time trace -/

def step (tr : Tr) (time g : Nat → Rat) (on : Nat → Bool) (k : Nat) (p : Run) : Run :=
  if on (k + 1) = false then rest (g (k + 1)) (time (k + 1))
  else if g (k + 1) = g k then p
  else ⟨value tr p (time (k + 1)), g (k + 1), time (k + 1), true⟩

theorem run_succ (tr : Tr) (time g : Nat → Rat) (on : Nat → Bool) (k : Nat) :
    run tr time g on (k + 1) = step tr time g on k (run tr time g on k) := rfl

def trace (tr : Tr) (time g : Nat → Rat) (on : Nat → Bool) : Nat → Run → Nat → List Run
  | _, r, 0 => [r]
  | k, r, m + 1 => r :: trace tr time g on (k + 1) (step tr time g on k r) m

theorem trace_eq (tr : Tr) (time g : Nat → Rat) (on : Nat → Bool) (m : Nat) :
    ∀ k, trace tr time g on k (run tr time g on k) m = (List.range (m + 1)).map fun i => run tr time g on (k + i) := by
  induction m with
  | zero => intro k; rfl
  | succ m ih =>
    intro k
    rw [trace, ← run_succ, ih (k + 1), List.range_succ_eq_map (n := m + 1), List.map_cons, List.map_map]
    congr 1
    apply List.map_congr_left
    intro i _
    simp only [Function.comp_apply]
    congr 1
    omega

/-! ## The end-of-page morph at 60 Hz -/

def frameMs : Rat := 50 / 3

def frameTime (k : Nat) : Rat := k * frameMs

theorem frameTime_mono (i : Nat) : frameTime i ≤ frameTime (i + 1) := by
  unfold frameTime frameMs; push_cast; grind

/-- The tween's value at frame `k` of a push from `a` to `b` (`MorphTween.tween`). -/
def morphAt (a b : Rat) (k : Nat) : Rat := (MorphTween.tween a b (frameTime k)).value

def armOn (m : Nat → Rat) (k : Nat) : Bool := transitionsOn true (decide (Nav.morphingCut < m k))

/-- The three transitioned properties of the earn button at morph `m` (`Nav.earnMaxW`, `earnPad`, `earnOpacity`). -/
def props (v : Nav.Vp) : List (String × Tr × (Rat → Rat)) :=
  [("maxW", maxWTr, Nav.earnMaxW v false), ("pad", padTr, Nav.earnPad v false), ("opacity", opacityTr, Nav.earnOpacity false)]

def frames : Nat := 90

def traceOf (tr : Tr) (g : Nat → Rat) (on : Nat → Bool) : List Run :=
  trace tr frameTime g on 0 (run tr frameTime g on 0) frames

def dirtyAt (tr : Tr) (g : Nat → Rat) (rs : List Run) (k : Nat) : Bool :=
  match k, rs[k]? with
  | 0, _ => false
  | k + 1, some r => decide (g (k + 1) ≠ g k) || running tr r (frameTime (k + 1))
  | _, none => false

/-- `x` rounded to 4 decimals as a JSON number. -/
def q4 (x : Rat) : Lean.Json := .num ⟨(x * 10000 + 1 / 2).floor, 4⟩

/-- One property at one frame: the CSS value, what each arm shows, and whether each arm's style changed. -/
structure Row where
  css : Rat
  faithful : Rat
  arm : Rat
  dirtyF : Bool
  dirtyA : Bool

def rows (tr : Tr) (g : Nat → Rat) (m : Nat → Rat) : List Row :=
  let f := traceOf tr g faithfulOn
  let a := traceOf tr g (armOn m)
  (List.range (frames + 1)).map fun k =>
    ⟨g k, value tr (f.getD k default) (frameTime k), value tr (a.getD k default) (frameTime k), dirtyAt tr g f k,
      dirtyAt tr g a k⟩

def rowJson (r : Row) : Lean.Json :=
  Lean.Json.mkObj [("css", q4 r.css), ("faithful", q4 r.faithful), ("arm", q4 r.arm), ("dirtyF", .bool r.dirtyF),
    ("dirtyA", .bool r.dirtyA)]

/-- Frames with a style change in each arm, and the last such frame. -/
structure Count where
  faithful : Nat
  arm : Nat
  lastF : Nat
  lastA : Nat
deriving Repr, BEq

def countOf (rs : List Row) : Count :=
  (rs.zip (List.range rs.length)).foldl (fun c (r, k) =>
    ⟨c.faithful + (if r.dirtyF then 1 else 0), c.arm + (if r.dirtyA then 1 else 0), if r.dirtyF then k else c.lastF,
      if r.dirtyA then k else c.lastA⟩) ⟨0, 0, 0, 0⟩

def viewports : List (String × Nav.Vp) := [("desktop", ⟨1440, 900⟩), ("phone", ⟨390, 844⟩)]

def pushes : List (String × Rat × Rat) := [("open", 0, 1), ("close", 1, 0)]

def line (fn : String) (inp : List (String × Lean.Json)) (out : Lean.Json) : String :=
  (Lean.Json.mkObj [("fn", .str fn), ("in", Lean.Json.mkObj inp), ("out", out)]).compress

def trJson (name : String) (tr : Tr) : String :=
  line "transition" [("property", .str name)]
    (Lean.Json.mkObj [("delayMs", q4 tr.delay), ("durMs", q4 tr.dur),
      ("curve", .arr #[q4 tr.curve.x1, q4 tr.curve.y1, q4 tr.curve.x2, q4 tr.curve.y2])])

def frameLines (vn : String) (v : Nav.Vp) (pn : String) (a b : Rat) : List String :=
  let m := morphAt a b
  let per := (props v).map fun (n, tr, f) => (n, rows tr (fun k => f (m k)) m)
  (List.range (frames + 1)).map fun k =>
    line "frame" [("viewport", .str vn), ("push", .str pn), ("k", Lean.toJson k)]
      (Lean.Json.mkObj ([("t", q4 (frameTime k)), ("m", q4 (m k)), ("morphing", .bool (decide (Nav.morphingCut < m k)))] ++
        per.map fun (n, rs) => (n, rowJson (rs.getD k ⟨0, 0, 0, false, false⟩))))

def countLines (vn : String) (v : Nav.Vp) (pn : String) (a b : Rat) : List String :=
  let m := morphAt a b
  (props v).map fun (n, tr, f) =>
    let c := countOf (rows tr (fun k => f (m k)) m)
    line "work" [("viewport", .str vn), ("push", .str pn), ("property", .str n), ("frames", Lean.toJson (frames + 1))]
      (Lean.Json.mkObj [("faithful", Lean.toJson c.faithful), ("arm", Lean.toJson c.arm),
        ("lastFaithful", Lean.toJson c.lastF), ("lastArm", Lean.toJson c.lastA)])

/-- The work count of property `n` on one push. -/
def countFor (v : Nav.Vp) (a b : Rat) (n : String) : Option Count :=
  let m := morphAt a b
  ((props v).find? (·.1 == n)).map fun (_, tr, f) => countOf (rows tr (fun k => f (m k)) m)

/-- Property `n` at frame `k` of one push. -/
def rowAt (v : Nav.Vp) (a b : Rat) (n : String) (k : Nat) : Option Row :=
  let m := morphAt a b
  ((props v).find? (·.1 == n)).bind fun (_, tr, f) => (rows tr (fun k => f (m k)) m)[k]?

#guard countFor ⟨1440, 900⟩ 0 1 "maxW" == some ⟨43, 3, 43, 3⟩
#guard countFor ⟨1440, 900⟩ 0 1 "opacity" == some ⟨29, 3, 29, 3⟩
#guard countFor ⟨1440, 900⟩ 1 0 "maxW" == some ⟨65, 65, 81, 81⟩
#guard (rowAt ⟨1440, 900⟩ 0 1 "maxW" 10).all fun r => r.arm == 0 && r.faithful > 150
#guard (rowAt ⟨1440, 900⟩ 0 1 "opacity" 10).all fun r => r.arm == 0 && r.faithful == 1

/-- The golden lines `packages/contracts/golden/parts/nav-earn.jsonl`. -/
def lines : List String :=
  ([false, true].flatMap fun f => [false, true].map fun mo =>
      line "transitionsOn" [("flag", .bool f), ("morphing", .bool mo)] (.bool (transitionsOn f mo))) ++
  [trJson "max-width" maxWTr, trJson "padding-inline" padTr, trJson "opacity" opacityTr] ++
  viewports.flatMap (fun (vn, v) => pushes.flatMap fun (pn, a, b) => countLines vn v pn a b) ++
  viewports.flatMap (fun (vn, v) => pushes.flatMap fun (pn, a, b) => frameLines vn v pn a b)

def goldenText : String := String.join (lines.map (· ++ "\n"))

/-- Print the golden text, or with `--check <file>` compare it; exit 1 on a difference. -/
def gen (args : List String) : IO UInt32 := do
  match args with
  | ["--check", path] =>
    if (← IO.FS.readFile path) == goldenText then
      IO.eprintln s!"nav-earn golden: {path} is up to date ({lines.length} lines)"
      return 0
    IO.eprintln s!"nav-earn golden: {path} differs from the generated text"
    return 1
  | _ =>
    IO.print goldenText
    return 0

end Fw.Parts.NavEarnOpt
