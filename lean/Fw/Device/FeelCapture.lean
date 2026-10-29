import Fw.Device.Feel
/-!
# What the phone feel session captures while the person scrolls

The page records, for every native animation frame of a visit, its time and `scrollY`; for every frame the opacity of each hero
card; every page call of `scrollTo`; and every start of the nav tween. This module reduces those series to the counts of
`Fw.Device.Feel.Capture`. Units: times in hundredths of a millisecond, scroll positions in tenths of a pixel, opacity in per mille.
-/
namespace Fw.Device.Feel

/-- A frame longer than this many hundredths of a millisecond is long (16.7 ms). -/
def long17Cs : Nat := 1670

/-- The second limit (33 ms). -/
def long33Cs : Nat := 3300

/-- A hero card dips when its opacity falls this far (per mille) below a frame before and a frame after. -/
def blinkDrop : Nat := 150

/-- The dip is closed by frames at most this far apart: the opacity falls and returns within this many frames. -/
def blinkWithin : Nat := 8

/-- After this many ms without a finger or a scroll move the page-side counting window is idle. -/
def idleMs : Nat := 1500

/-- Height of a zone in px (the counts lane's zone). -/
def zonePx : Nat := 500

/-- Gap between each frame time and the next. -/
def gaps : List Nat → List Nat
  | a :: b :: rest => (b - a) :: gaps (b :: rest)
  | _ => []

theorem gaps_length (ts : List Nat) : (gaps ts).length = ts.length - 1 := by
  induction ts with
  | nil => rfl
  | cons a t ih =>
    cases t with
    | nil => rfl
    | cons b r => simp only [gaps, List.length_cons] at *; omega

/-- For each frame gap, whether the scroll position changed across it. -/
def diffs (ys : List Nat) : List Bool := (ys.zip ys.tail).map fun p => p.1 != p.2

/-- A gap is moving when the scroll moved across it or across the gap before it: a stall after a move is still the scroll's stall. -/
def movingFlags (ds : List Bool) : List Bool := (ds.zip (false :: ds)).map fun p => p.1 || p.2

/-- Moving gaps longer than `thr`. -/
def longCount (thr : Nat) (ts ys : List Nat) : Nat :=
  ((gaps ts).zip (movingFlags (diffs ys))).countP fun p => p.2 && thr < p.1

def movingCount (ts ys : List Nat) : Nat :=
  ((gaps ts).zip (movingFlags (diffs ys))).countP fun p => p.2

theorem longCount_mono {a b : Nat} (h : a ≤ b) (ts ys : List Nat) : longCount b ts ys ≤ longCount a ts ys := by
  unfold longCount
  apply List.countP_mono_left
  intro p _ hp
  simp only [Bool.and_eq_true, decide_eq_true_eq] at hp ⊢
  exact ⟨hp.1, by omega⟩

theorem longCount_le_moving (thr : Nat) (ts ys : List Nat) : longCount thr ts ys ≤ movingCount ts ys := by
  unfold longCount movingCount
  apply List.countP_mono_left
  intro p _ hp
  simp only [Bool.and_eq_true] at hp
  exact hp.1

theorem long33_le_long17 (ts ys : List Nat) : longCount long33Cs ts ys ≤ longCount long17Cs ts ys :=
  longCount_mono (by decide) ts ys

theorem longCount_nil (thr : Nat) : longCount thr [] [] = 0 := rfl

theorem longCount_still : longCount long17Cs [0, 5000, 20000, 90000] [300, 300, 300, 300] = 0 := by decide

theorem longCount_stall : longCount long17Cs [0, 1600, 3200, 8200, 9800] [0, 10, 20, 30, 40] = 1 := by decide

theorem longCount_two_limits : longCount long33Cs [0, 1600, 3200, 8200, 9800] [0, 10, 20, 30, 40] = 1
    ∧ longCount long33Cs [0, 1600, 3200, 6000, 7600] [0, 10, 20, 30, 40] = 0 := by decide

/-- Number of direction changes of the scroll: a move up after a move down, or the reverse. -/
def flips : List Bool → Nat
  | a :: b :: r => (if a != b then 1 else 0) + flips (b :: r)
  | _ => 0

/-- Directions of the moves of a scroll series (true = down), still gaps left out. -/
def dirs (ys : List Nat) : List Bool :=
  (ys.zip ys.tail).filterMap fun p => if p.1 < p.2 then some true else if p.2 < p.1 then some false else none

def reversals (ys : List Nat) : Nat := flips (dirs ys)

/-- A page call of `scrollTo`: when it ran, where the scroll was, where it asked to be. -/
structure Pin where
  t : Nat
  from_ : Nat
  to_ : Nat
  deriving DecidableEq

/-- The scroll move across the last frame at or before `t`: positive is down. Zero before the second frame. -/
def dirAt (ts ys : List Nat) (t : Nat) : Int :=
  let k := (ts.filter (· ≤ t)).length
  if k < 2 then 0 else (ys.getD (k - 1) 0 : Int) - (ys.getD (k - 2) 0 : Int)

/-- The pin goes against the finger: the page asks for a move opposite to the move the scroll was making. -/
def fightAt (ts ys : List Nat) (p : Pin) : Bool :=
  decide (dirAt ts ys p.t * ((p.to_ : Int) - (p.from_ : Int)) < 0)

def fights (ts ys : List Nat) (ps : List Pin) : Nat := ps.countP (fightAt ts ys)

theorem fights_le_pins (ts ys : List Nat) (ps : List Pin) : fights ts ys ps ≤ ps.length := List.countP_le_length

theorem fightAt_noop (ts ys : List Nat) (t y : Nat) : fightAt ts ys ⟨t, y, y⟩ = false := by simp [fightAt]

theorem fightAt_still (ts ys : List Nat) (p : Pin) (h : dirAt ts ys p.t = 0) : fightAt ts ys p = false := by simp [fightAt, h]

theorem fightAt_pin_up {ts ys : List Nat} {p : Pin} (hd : 0 < dirAt ts ys p.t) (hp : p.to_ < p.from_) : fightAt ts ys p = true := by
  simp only [fightAt, decide_eq_true_eq]
  have : (p.to_ : Int) - p.from_ < 0 := by omega
  exact Int.mul_neg_of_pos_of_neg hd this

theorem fightAt_pin_down {ts ys : List Nat} {p : Pin} (hd : dirAt ts ys p.t < 0) (hp : p.from_ < p.to_) : fightAt ts ys p = true := by
  simp only [fightAt, decide_eq_true_eq]
  have : 0 < (p.to_ : Int) - p.from_ := by omega
  exact Int.mul_neg_of_neg_of_pos hd this

theorem fightAt_same_way {ts ys : List Nat} {p : Pin} (hd : 0 < dirAt ts ys p.t) (hp : p.from_ ≤ p.to_) : fightAt ts ys p = false := by
  simp only [fightAt, decide_eq_false_iff_not]
  have : 0 ≤ (p.to_ : Int) - p.from_ := by omega
  exact Int.not_lt.2 (Int.mul_nonneg (Int.le_of_lt hd) this)

/-- A tween start that begins between rest and target: the nav tween was re-aimed in flight (from and to in per mille). -/
def retargets (starts : List (Nat × Nat)) : Nat := starts.countP fun p => 0 < p.1 && p.1 < 1000

theorem retarget_mid {f t : Nat} (h0 : 0 < f) (h1 : f < 1000) : retargets [(f, t)] = 1 := by simp [retargets, h0, h1]

theorem retarget_rest (t : Nat) : retargets [(0, t)] = 0 := by simp [retargets]

theorem retarget_end (t : Nat) : retargets [(1000, t)] = 0 := by simp [retargets]

/-- Frame `k` of an opacity series dips: a frame before it and a frame after it, at most `blinkWithin` frames apart, are both
at least `blinkDrop` above it. -/
def dipAt (o : List Nat) (k : Nat) : Bool :=
  let v := o.getD k 0
  (List.range k).any fun i => k - i ≤ blinkWithin && blinkDrop + v ≤ o.getD i 0 &&
    (List.range' (k + 1) blinkWithin).any fun j => j - i ≤ blinkWithin && blinkDrop + v ≤ o.getD j 0

/-- Hero-card blinks of one card: runs of consecutive dipping frames, each counted once. -/
def blinks (o : List Nat) : Nat :=
  (List.range o.length).countP fun k => dipAt o k && !(0 < k && dipAt o (k - 1))

def blinksOf (cards : List (List Nat)) : Nat := (cards.map blinks).foldl (· + ·) 0

theorem blinks_nil : blinks [] = 0 := rfl

theorem blinks_le_length (o : List Nat) : blinks o ≤ o.length := by
  unfold blinks
  have := List.countP_le_length (l := List.range o.length) (p := fun k => dipAt o k && !(0 < k && dipAt o (k - 1)))
  simpa using this

theorem blink_dip : blinks [1000, 1000, 300, 1000, 1000] = 1 := by decide

theorem blink_wide_dip : blinks [1000, 300, 300, 300, 1000] = 1 := by decide

theorem blink_two : blinks [1000, 300, 1000, 1000, 1000, 300, 1000] = 2 := by decide

theorem blink_small_dip : blinks [1000, 900, 1000, 1000] = 0 := by decide

theorem blink_step_down : blinks [1000, 1000, 300, 300, 300] = 0 := by decide

theorem blink_slow_return : blinks [1000, 300, 300, 300, 300, 300, 300, 300, 300, 300, 1000] = 0 := by decide

theorem blink_constant : blinks (List.replicate 12 700) = 0 := by decide

theorem blink_fade_out : blinks [1000, 900, 800, 700, 600, 500, 400, 300] = 0 := by decide

/-- Work in a zone: style recalculations, layouts and paints (positions 0 to 2 of the counts lane's record types). -/
def workOf (c : List Nat) : Nat := c.getD 0 0 + c.getD 1 0 + c.getD 2 0

theorem topZone_nil : topZone [] = none := rfl

theorem foldl_max_ge (w : List Nat) (a : Nat) : a ≤ w.foldl max a := by
  induction w generalizing a with
  | nil => exact Nat.le_refl _
  | cons x r ih => exact Nat.le_trans (Nat.le_max_left a x) (ih _)

theorem le_foldl_max (w : List Nat) (a : Nat) : ∀ j, j < w.length → w.getD j 0 ≤ w.foldl max a := by
  induction w generalizing a with
  | nil => intro j hj; simp at hj
  | cons x r ih =>
    intro j hj
    cases j with
    | zero => simp only [List.getD_cons_zero, List.foldl_cons]; exact Nat.le_trans (Nat.le_max_right a x) (foldl_max_ge r _)
    | succ k => simp only [List.getD_cons_succ, List.foldl_cons]; exact ih _ k (by simpa using hj)

/-- The zone named is a zone with the most work, and it has some. -/
theorem topZone_max {w : List Nat} {i : Nat} (h : topZone w = some i) : ∀ j, j < w.length → w.getD j 0 ≤ w.getD i 0 := by
  intro j hj
  unfold topZone at h
  simp only at h
  split at h
  · simp at h
  · have hi := List.findIdx?_eq_some_iff_getElem.1 h
    obtain ⟨hlt, hp, _⟩ := hi
    have e : w[i] = w.foldl max 0 := by simpa using hp
    have : w.getD i 0 = w.foldl max 0 := by simp [List.getD_eq_getElem?_getD, hlt, e]
    rw [this]
    exact le_foldl_max w 0 j hj

theorem topZone_pos {w : List Nat} {i : Nat} (h : topZone w = some i) : 0 < w.getD i 0 := by
  have hm := topZone_max h
  unfold topZone at h
  simp only at h
  split at h
  · simp at h
  · rename_i hne
    have hi := List.findIdx?_eq_some_iff_getElem.1 h
    obtain ⟨hlt, hp, _⟩ := hi
    have e : w[i] = w.foldl max 0 := by simpa using hp
    have : w.getD i 0 = w.foldl max 0 := by simp [List.getD_eq_getElem?_getD, hlt, e]
    rw [this]
    omega

theorem topZone_zero (n : Nat) : topZone (List.replicate n 0) = none := by
  unfold topZone
  have : (List.replicate n 0).foldl max 0 = 0 := by
    induction n with
    | zero => rfl
    | succ k ih => simpa [List.replicate_succ] using ih
  simp [this]

/-- The capture of a visit from its series. `zones` is the counts lane's record counts per 500 px zone. -/
def captureOf (ts ys : List Nat) (pins : List Pin) (starts : List (Nat × Nat)) (cards : List (List Nat))
    (zones : List (List Nat)) : Capture :=
  ⟨movingCount ts ys, longCount long17Cs ts ys, longCount long33Cs ts ys, pins.length, fights ts ys pins, reversals ys,
    retargets starts, blinksOf cards, zones.map workOf⟩

theorem captureOf_long (ts ys : List Nat) (pins starts cards zones) :
    (captureOf ts ys pins starts cards zones).long33 ≤ (captureOf ts ys pins starts cards zones).long17 :=
  long33_le_long17 ts ys

theorem captureOf_fights (ts ys : List Nat) (pins starts cards zones) :
    (captureOf ts ys pins starts cards zones).fights ≤ (captureOf ts ys pins starts cards zones).pins :=
  fights_le_pins ts ys pins

/-- Who closed the inspector connection. -/
inductive Cause where
  | self | phoneNotOnUsb | otherClient | unknown
  deriving DecidableEq

def Cause.code : Cause → String
  | .self => "self" | .phoneNotOnUsb => "phoneNotOnUsb" | .otherClient => "otherClient" | .unknown => "unknown"

/-- A closed connection is named from a probe of the USB bus taken at the close: the phone absent is the cause whatever the proxy
reported; another client is named only when the phone is on USB. `usb` is none when the probe could not run. -/
def closeCause (selfClosed : Bool) (usb : Option Bool) : Cause :=
  if selfClosed then .self else match usb with
    | some false => .phoneNotOnUsb
    | some true => .otherClient
    | none => .unknown

theorem closeCause_self (u : Option Bool) : closeCause true u = .self := rfl

theorem closeCause_absent : closeCause false (some false) = .phoneNotOnUsb := rfl

theorem closeCause_present : closeCause false (some true) = .otherClient := rfl

theorem closeCause_unprobed : closeCause false none = .unknown := rfl

end Fw.Device.Feel
