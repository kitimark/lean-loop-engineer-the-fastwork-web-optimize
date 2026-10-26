import Fw.Parts.PlatformSweep
import Fw.Engine.VisualTimed
import Fw.Engine.ResourceVerdict
import Fw.Site.Breakpoints
/-!
# platform.entries: entry animations, count-up and the search typing of the stage visuals (P5 port, `faithful`)

Restated (not copied) from the original snapshot, read independently of the TS part:

* `snapshot/site-pretty/_app/immutable/assets/2.gBuqKVzi.css`: the keyframes and `animation:` shorthands
  `start-selling-cred-card-in` (6516-6522, 7517), `profile-phone-in` (7512-7525), the six `secure-network-*-in` (7045-7101,
  7104-7170), `invoice-card-in` / `invoice-i-row-in` / `orders-card-in` (8580-8610, 8700-8720, 8846-8855),
  `agents-ask-in` / `-out` (9074-9115, 9129-9145). Every one is a two-keyframe `from -> to` run with `both` fill and
  `cubic-bezier(0.16, 1, 0.3, 1)`.
* `.../nodes/2.DyWL8TcE.js` 11996-12040: the profile count-up (180 ms delay, 1080 ms, ease-out cubic, `Math.round`);
  11659-11700 (`b(() => ...)`): the search typing schedule (700 ms lead, 32 ms per typed char, 280 ms first reveal and
  700 ms swap, 3000 ms hold, 18 ms per erased char).

All values `Rat`. No `Float`. This is the exact "original" an optimized version is compared against.
-/
namespace Fw.Parts.PlatformEntries
open Fw.Parts.PlatformSweep (frac frac_mem)

/-! ## The easing curve -/

/-- A CSS cubic-bezier with control points `(x_1, y_1), (x_2, y_2)`. -/
structure Bez where
  x1 : Rat
  y1 : Rat
  x2 : Rat
  y2 : Rat
deriving Repr

/-- The curve every entry uses. -/
def spring : Bez := ⟨4 / 25, 1, 3 / 10, 1⟩

/-- The `x` coordinate at curve parameter `u`. -/
def bx (b : Bez) (u : Rat) : Rat :=
  3 * (1 - u) * (1 - u) * u * b.x1 + 3 * (1 - u) * u * u * b.x2 + u * u * u

/-- The `y` coordinate at curve parameter `u`. -/
def by' (b : Bez) (u : Rat) : Rat :=
  3 * (1 - u) * (1 - u) * u * b.y1 + 3 * (1 - u) * u * u * b.y2 + u * u * u

/-- Bisection on `B_x(u) = x`, `n` halvings of `[lo, hi]`. -/
def bis (b : Bez) (x : Rat) : Nat → Rat × Rat → Rat × Rat
  | 0, p => p
  | n + 1, (lo, hi) => if bx b ((lo + hi) / 2) < x then bis b x n ((lo + hi) / 2, hi) else bis b x n (lo, (lo + hi) / 2)

/-- Number of halvings (resolution `2^(-24)`). -/
def steps : Nat := 24

/-- The parameter whose `x` is closest to `x` after `N` halvings, mid-point. -/
def solve (b : Bez) (x : Rat) : Rat :=
  let p := bis b x steps (0, 1)
  (p.1 + p.2) / 2

/-- The eased progress for a linear progress `x`. -/
def ease (b : Bez) (x : Rat) : Rat := if x ≤ 0 then 0 else if 1 ≤ x then 1 else by' b (solve b x)

/-- The bisection keeps its interval inside `[0, 1]` and ordered. -/
theorem bis_inv (b : Bez) (x : Rat) (n : Nat) :
    ∀ lo hi : Rat, 0 ≤ lo → lo ≤ hi → hi ≤ 1 →
      0 ≤ (bis b x n (lo, hi)).1 ∧ (bis b x n (lo, hi)).1 ≤ (bis b x n (lo, hi)).2 ∧ (bis b x n (lo, hi)).2 ≤ 1 := by
  induction n with
  | zero => intro lo hi h0 h1 h2; simp [bis]; grind
  | succ n ih =>
    intro lo hi h0 h1 h2
    simp only [bis]
    split
    · exact ih _ _ (by grind) (by grind) h2
    · exact ih _ _ h0 (by grind) (by grind)

/-- The solved parameter lies in `[0, 1]`. -/
theorem solve_mem (b : Bez) (x : Rat) : 0 ≤ solve b x ∧ solve b x ≤ 1 := by
  have := bis_inv b x steps 0 1 (by grind) (by grind) (by grind)
  unfold solve
  grind

/-- For the spring curve (`y_1 = y_2 = 1`) the `y` coordinate is `1 - (1-u)^3`. -/
theorem spring_by (u : Rat) : by' spring u = 1 - (1 - u) * (1 - u) * (1 - u) := by
  unfold by' spring; grind

/-- The spring ease stays in `[0, 1]`. Entries never overshoot. -/
theorem ease_mem (x : Rat) : 0 ≤ ease spring x ∧ ease spring x ≤ 1 := by
  unfold ease
  split
  · grind
  split
  · grind
  · have hu := solve_mem spring x
    rw [spring_by]
    generalize solve spring x = u at *
    have h0 : 0 ≤ 1 - u := by grind
    have h1 : 1 - u ≤ 1 := by grind
    have h2 : (1 - u) * (1 - u) ≤ 1 := by
      have := Rat.mul_le_mul_of_nonneg_left h1 h0
      grind
    have h3 : 0 ≤ (1 - u) * (1 - u) := Rat.mul_nonneg h0 h0
    have h4 : (1 - u) * (1 - u) * (1 - u) ≤ 1 := by
      have := Rat.mul_le_mul_of_nonneg_right h2 h0
      grind
    have h5 : 0 ≤ (1 - u) * (1 - u) * (1 - u) := Rat.mul_nonneg h3 h0
    grind

/-- The spring ease starts at 0 and ends at 1. -/
theorem ease_ends : ease spring 0 = 0 ∧ ease spring 1 = 1 := by
  constructor <;> decide +kernel

/-- A quotient with a non-positive numerator is non-positive. -/
theorem div_nonpos' (a d : Rat) (hd : 0 < d) (h : a ≤ 0) : a / d ≤ 0 := by
  by_cases hc : a / d ≤ 0
  · exact hc
  · have hq : 0 < a / d := by grind
    have := Rat.mul_pos hq hd
    have e : a / d * d = a := Rat.div_mul_cancel (by grind)
    grind

/-- A quotient of a number at least the divisor is at least 1. -/
theorem one_le_div' (a d : Rat) (hd : 0 < d) (h : d ≤ a) : 1 ≤ a / d := by
  by_cases hc : 1 ≤ a / d
  · exact hc
  · have e : a / d * d = a := Rat.div_mul_cancel (by grind)
    have h2 : 0 < (1 - a / d) * d := Rat.mul_pos (by grind) hd
    grind

/-! ## Entries -/

/-- One animated property: from-value, to-value. `key` names `opacity`, `translateX`, `translateY`, `scale`, `scaleX` or `blur` (px). -/
structure Tr where
  key : String
  a : Rat
  b : Rat
deriving Repr

/-- One entry animation: keyframe name, duration and delay in ms, the properties. -/
structure Entry where
  name : String
  dur : Rat
  delay : Rat
  trs : List Tr
deriving Repr

/-- Fade + lift + blur used by the credibility cards and the profile phone. -/
def liftBlur : List Tr :=
  [⟨"opacity", 0, 1⟩, ⟨"translateY", 18, 0⟩, ⟨"scale", 24 / 25, 1⟩, ⟨"blur", 8, 0⟩]

/-- Credibility card `i` (delay `70 i` ms, `--cred-enter-delay`). -/
def credCard (i : Nat) : Entry := ⟨"cred-card-in", 420, 70 * i, liftBlur⟩

/-- Profile phone. -/
def profilePhone : Entry := ⟨"profile-phone-in", 620, 0, liftBlur⟩

/-- Secure-network rings. -/
def rings : Entry := ⟨"secure-network-rings-in", 480, 0, [⟨"opacity", 0, 1⟩, ⟨"scale", 26 / 25, 1⟩]⟩

/-- Left face. -/
def faceLeft : Entry := ⟨"secure-network-face-left-in", 320, 0, [⟨"opacity", 0, 1⟩, ⟨"translateX", -8, 0⟩]⟩

/-- Right face. -/
def faceRight : Entry := ⟨"secure-network-face-right-in", 320, 0, [⟨"opacity", 0, 1⟩, ⟨"translateX", 8, 0⟩]⟩

/-- Dash. -/
def dash : Entry := ⟨"secure-network-dash-in", 260, 60, [⟨"opacity", 0, 1⟩, ⟨"scaleX", 0, 1⟩]⟩

/-- Shield. -/
def shield : Entry := ⟨"secure-network-shield-in", 420, 180, [⟨"opacity", 0, 1⟩, ⟨"scale", 22 / 25, 1⟩]⟩

/-- Logo mark. -/
def logo : Entry := ⟨"secure-network-logo-in", 280, 680, [⟨"opacity", 0, 1⟩, ⟨"scale", 7 / 10, 1⟩]⟩

/-- Delay of flag number `k` (1-based child index): 600, 560, 520, 520, 560, 600 ms; every other `k`
(including `k = 0`) gets 600. -/
def flagDelay : Nat → Rat
  | 1 => 600 | 2 => 560 | 3 => 520 | 4 => 520 | 5 => 560 | _ => 600

/-- Flag `k`. -/
def flag (k : Nat) : Entry := ⟨"secure-network-flag-in", 280, flagDelay k, [⟨"opacity", 0, 1⟩, ⟨"scale", 41 / 50, 1⟩]⟩

/-- Invoice card (the `invoice-i` variant of the last row). -/
def invoiceCard : Entry := ⟨"invoice-card-in", 560, 620, [⟨"opacity", 0, 1⟩, ⟨"translateY", 22, 0⟩, ⟨"scale", 47 / 50, 1⟩]⟩

/-- Orders row `i` (delay `140 i` ms, `--orders-card-delay`). -/
def orderRow (i : Nat) : Entry := ⟨"invoice-i-row-in", 620, 140 * i, [⟨"opacity", 0, 1⟩, ⟨"translateX", 20, 0⟩]⟩

/-- Search title, field and service `i` entering (delay `140 i` ms). -/
def askIn (i : Nat) : Entry := ⟨"agents-ask-in", 560, 140 * i, [⟨"opacity", 0, 1⟩, ⟨"translateY", 10, 0⟩]⟩

/-- Search service `i` leaving. -/
def askOut (i : Nat) : Entry := ⟨"agents-ask-out", 560, 140 * i, [⟨"opacity", 1, 0⟩, ⟨"translateY", 0, 10⟩]⟩

/-- Linear progress of an entry `t` ms after its animation was started (`both` fill). -/
def lin (e : Entry) (t : Rat) : Rat := (t - e.delay) / e.dur

/-- Eased progress on the spring curve. -/
def progress (e : Entry) (t : Rat) : Rat := ease spring (lin e t)

/-- A property's value `t` ms in. -/
def value (e : Entry) (tr : Tr) (t : Rat) : Rat := tr.a + (tr.b - tr.a) * progress e t

/-- Before the delay the entry sits on its first keyframe (fill `both`). -/
theorem progress_before (e : Entry) (t : Rat) (hD : 0 < e.dur) (h : t ≤ e.delay) : progress e t = 0 := by
  unfold progress lin ease
  have : (t - e.delay) / e.dur ≤ 0 := div_nonpos' _ _ hD (by grind)
  simp [this]

/-- After delay plus duration it sits on its last keyframe. -/
theorem progress_after (e : Entry) (t : Rat) (hD : 0 < e.dur) (h : e.delay + e.dur ≤ t) : progress e t = 1 := by
  unfold progress lin ease
  have h1 : 1 ≤ (t - e.delay) / e.dur := one_le_div' _ _ hD (by grind)
  have h2 : ¬ (t - e.delay) / e.dur ≤ 0 := by grind
  simp [h1, h2]

/-- The progress stays in `[0, 1]`. -/
theorem progress_mem (e : Entry) (t : Rat) : 0 ≤ progress e t ∧ progress e t ≤ 1 := ease_mem _

/-- A property stays between its two keyframe values. -/
theorem value_between (e : Entry) (tr : Tr) (t : Rat) :
    min tr.a tr.b ≤ value e tr t ∧ value e tr t ≤ max tr.a tr.b := by
  have hm := progress_mem e t
  unfold value
  generalize progress e t = k at *
  by_cases hs : tr.a ≤ tr.b
  · have := Rat.mul_nonneg (show 0 ≤ tr.b - tr.a by grind) hm.1
    have := Rat.mul_le_mul_of_nonneg_left hm.2 (show 0 ≤ tr.b - tr.a by grind)
    grind
  · have := Rat.mul_nonneg (show 0 ≤ tr.a - tr.b by grind) hm.1
    have := Rat.mul_le_mul_of_nonneg_left hm.2 (show 0 ≤ tr.a - tr.b by grind)
    grind

/-- The entries only run when not static (reduced motion shows the end state at once). -/
def play (visible reduce : Bool) : Bool := visible && !reduce

/-! ## Count-up of the profile stats -/

/-- Delay before the count starts (ms). -/
def countDelay : Rat := 180

/-- Length of the count (ms). -/
def countDur : Rat := 1080

/-- Ease-out cubic of the count. -/
def easeOut (x : Rat) : Rat := 1 - (1 - x) * (1 - x) * (1 - x)

/-- JS `Math.round`. Half rounds up. -/
def jsRound (x : Rat) : Int := (x + 1 / 2).floor

/-- The shown number for target `n`, `t` ms after the stage became visible. -/
def countAt (n : Nat) (t : Rat) : Int :=
  if t < countDelay then 0 else jsRound ((n : Rat) * easeOut (min 1 ((t - countDelay) / countDur)))

#guard countAt 240 0 == 0
#guard countAt 240 1260 == 240
#guard countAt 48 9999 == 48
#guard countAt 5 (180 + 540) == 4

/-- After the count the target is shown exactly. -/
theorem count_done (n : Nat) (t : Rat) (h : 1260 ≤ t) : countAt n t = n := by
  unfold countAt
  have h1 : ¬ t < countDelay := by unfold countDelay; grind
  have h2 : min 1 ((t - countDelay) / countDur) = 1 := by
    have : 1 ≤ (t - countDelay) / countDur := by
      apply one_le_div' _ _ (by unfold countDur; decide)
      unfold countDelay countDur; grind
    grind
  simp only [h1, h2, ite_false]
  unfold easeOut jsRound
  have e1 : (n : Rat) * (1 - (1 - 1) * (1 - 1) * (1 - 1)) + 1 / 2 = 1 / 2 + ((n : Int) : Rat) := by push_cast; grind
  rw [e1, Rat.floor_add_intCast]
  have : (1/2 : Rat).floor = 0 := by decide +kernel
  grind

/-! ## Search typing -/

/-- Delay from becoming visible to the first typed character (ms). -/
def askLead : Rat := 700
/-- Ms per typed character. -/
def typeStep : Rat := 32
/-- Ms per erased character. -/
def eraseStep : Rat := 18
/-- Ms the finished query is held. -/
def holdMs : Rat := 3000
/-- First reveal wait (ms): the results appear 280 ms after the first query is typed. -/
def firstReveal : Rat := 280
/-- Swap wait (ms) of every later topic (the old list leaves for this long). -/
def swapMs : Rat := 700

/-- Duration of one topic with a query of `L` characters. -/
def topicDur (L : Nat) (reveal : Rat) : Rat := typeStep * L + reveal + holdMs + eraseStep * L

/-- Result of the view: shown query length, query topic, topic of the visible list, list leaving, results visible, caret visible. -/
structure View where
  len : Nat
  topic : Nat
  shown : Nat
  leaving : Bool
  results : Bool
  caret : Bool
deriving Repr, DecidableEq

/-- Floor to a natural number. -/
def fl (x : Rat) : Nat := x.floor.toNat

/-- The query length `τ` ms into a topic of length `L` whose reveal wait is `r` (`⌊·⌋_ℕ` is
`fl`, `∸` truncated subtraction). -/
def lenAt (L : Nat) (reveal τ : Rat) : Nat :=
  if τ < typeStep * L then min L (fl (τ / typeStep) + 1)
  else if τ < typeStep * L + reveal + holdMs then L
  else L - (fl ((τ - (typeStep * L + reveal + holdMs)) / eraseStep) + 1)

/-- One topic's view. `prev` is the topic whose list was shown before; `first` picks the 280 ms reveal, else the
700 ms swap. -/
def topicView (idx prev L : Nat) (first : Bool) (τ : Rat) : View :=
  let reveal := if first then firstReveal else swapMs
  let typed := typeStep * L
  { len := lenAt L reveal τ, topic := idx,
    shown := if typed ≤ τ then idx else prev,
    leaving := !first && typed ≤ τ && τ < typed + swapMs,
    results := !first || typed + firstReveal ≤ τ,
    caret := true }

/-- Walk the topic list: the first entry whose duration holds `r`, with `r` made relative to that entry. -/
def locate : List (Nat × Nat) → Rat → Option (Nat × Nat × Rat)
  | [], _ => none
  | (i, L) :: rest, r => if r < topicDur L swapMs then some (i, L, r) else locate rest (r - topicDur L swapMs)

/-- Cycle length: all topics except the first run in turn, then the first again with the swap wait. -/
def cycleLen (xs : List (Nat × Nat)) : Rat := (xs.map fun p => topicDur p.2 swapMs).sum

/-- Wrap `r` into `[0, P)`. -/
def wrap (P r : Rat) : Rat := r - P * (r / P).floor

/-- The rotation after the first topic: topics `1, ..., n-1`, then `0` again, each with its query length. -/
def rotation (lens : List Nat) : List (Nat × Nat) :=
  match lens with
  | [] => []
  | L0 :: rest => (rest.zipIdx 1).map (fun p => (p.2, p.1)) ++ [(0, L0)]

/-- The repeating part, `r` ms after the first topic ended: wrap into the rotation, then locate the topic.
The list shown before topic `i` is the one of the previous topic in the rotation (`n - 1` before topic 0). -/
def cycView (lens : List Nat) (r : Rat) : View :=
  match locate (rotation lens) (wrap (cycleLen (rotation lens)) r) with
  | some (i, L, τ) => topicView i (if i = 0 then (lens.length - 1) else i - 1) L false τ
  | none => ⟨0, 0, 0, false, false, false⟩

/-- The view at time `t` after the stage became visible. `lens` are the query lengths in topic order.
Before `700` ms: empty. Then topic 0 once with the 280 ms reveal; then the rotation `1, 2, ..., n-1, 0` with the
700 ms swap, repeating. -/
def askView (lens : List Nat) (t : Rat) : View :=
  if t < askLead then ⟨0, 0, 0, false, false, false⟩
  else
    match lens with
    | [] => ⟨0, 0, 0, false, false, false⟩
    | L0 :: rest =>
      let τ0 := t - askLead
      if τ0 < topicDur L0 firstReveal then topicView 0 0 L0 true τ0
      else cycView (L0 :: rest) (τ0 - topicDur L0 firstReveal)

/-- Wrapping by a whole cycle changes nothing. -/
theorem wrap_periodic (P r : Rat) (hP : 0 < P) : wrap P (r + P) = wrap P r := by
  unfold wrap
  have h : (r + P) / P = r / P + 1 := by
    have e := Rat.mul_inv_cancel P (by grind)
    rw [Rat.div_def, Rat.div_def]
    grind
  rw [h, Rat.floor_add_one]
  push_cast
  grind

/-- The repeating part is periodic in the rotation length. -/
theorem cycView_periodic (lens : List Nat) (r : Rat) (hP : 0 < cycleLen (rotation lens)) :
    cycView lens (r + cycleLen (rotation lens)) = cycView lens r := by
  unfold cycView
  rw [wrap_periodic _ _ hP]

/-- A view never shows more characters than the topic's query. -/
theorem lenAt_le (L : Nat) (reveal τ : Rat) : lenAt L reveal τ ≤ L := by
  unfold lenAt
  split
  · exact Nat.min_le_left _ _
  split
  · exact Nat.le_refl _
  · omega

/-- Nothing is typed before the 700 ms lead. -/
theorem before_lead (lens : List Nat) (t : Rat) (h : t < askLead) : (askView lens t).len = 0 := by
  unfold askView
  simp [h]

#guard (askView [23, 25, 22, 20] 0).len == 0
#guard (askView [23, 25, 22, 20] 700).len == 1
#guard (askView [23, 25, 22, 20] 732).len == 2
#guard (askView [23, 25, 22, 20] (700 + 32 * 23)).len == 23
#guard (askView [23, 25, 22, 20] (700 + 32 * 23 + 280)).results == true
#guard (askView [23, 25, 22, 20] (700 + 32 * 23 + 279)).results == false

/-! ## Typing in chunks of two is a subsample, not the same text (ledger n=22)

Counted in typing steps (`k` steps of 32 ms each), the original shows `min(L, k)` characters and the 2-per-step
variant shows `min(L, 2⌊ k/2 ⌋)`. The variant shows exactly the original's text at the even steps, starts
and ends equal, but differs at every odd step before the end: it is a subsample (fewer text writes), not a visual
no-op, so the visual verdict is "not E". -/

/-- Characters the original shows after `k` typing steps of a query of length `L`. -/
def typedO (L k : Nat) : Nat := min L k

/-- Characters the 2-per-step variant shows after `k` typing steps. -/
def typedV (L k : Nat) : Nat := min L (2 * (k / 2))

#guard typedO 5 3 == 3
#guard typedV 5 3 == 2
#guard typedV 5 6 == 5

/-- **typing_subsample.** The variant is the original sampled at even steps; it differs at step 1 for `L ≥ 2`; it
starts at 0 and, from step `L + 1` on, shows the whole query, like the original.

Fewer writes, the same first and last text, but not the same frames. -/
theorem typing_subsample (L k : Nat) :
    typedV L k = typedO L (2 * (k / 2)) ∧ (2 ≤ L → typedV L 1 ≠ typedO L 1) ∧
      (typedV L 0 = 0 ∧ typedO L 0 = 0) ∧ (L + 1 ≤ k → typedV L k = L ∧ typedO L k = L) := by
  simp only [typedV, typedO]
  refine ⟨trivial, fun h => by omega, by omega, fun h => by omega⟩

/-! ## fill-release: fill `backwards` and the end values as static style (`platform.entries:fill-release`) -/

section FillRelease
open Fw.Engine.VisualTimed
open Fw.Site.Breakpoints (Env rmNopref)

/-- One property of an entry as a timed track from the stage start, fill `both`, over the static value `base`. -/
def track (e : Entry) (tr : Tr) (base : Rat) : Track Rat := ⟨e.delay, e.dur, .both, value e tr, base⟩

/-- The value at the end of the active interval is the to-value. -/
theorem value_end (e : Entry) (tr : Tr) (hD : 0 < e.dur) : value e tr (e.delay + e.dur) = tr.b := by
  simp [value, progress_after e _ hD Rat.le_refl]; grind

/-- The track holds its to-value after the end. -/
theorem track_settles (e : Entry) (tr : Tr) (base : Rat) (hD : 0 < e.dur) : Settles (track e tr base) := by
  intro t h
  simp only [endVal, track] at *
  simp [value, progress_after e _ hD h, progress_after e _ hD Rat.le_refl]

/-- The variant's static value is the to-value. -/
theorem release_base (e : Entry) (tr : Tr) (base : Rat) (hD : 0 < e.dur) : (release (track e tr base)).base = tr.b :=
  value_end e tr hD

/-- The value shown in `env` at `t`: the track under no-preference, the reduced-motion static value `still` otherwise. -/
def shownIn (rel : Bool) (env : Env) (e : Entry) (tr : Tr) (base still t : Rat) : Rat :=
  if rmNopref.eval env then shown (if rel then release (track e tr base) else track e tr base) t else still

/-- Same look where the entries run. -/
theorem same_look_motion (env : Env) (e : Entry) (tr : Tr) (base still t : Rat) (hD : 0 < e.dur)
    (h : rmNopref.eval env = true) : shownIn true env e tr base still t = shownIn false env e tr base still t := by
  simp only [shownIn, h, ite_true, Bool.false_eq_true, ite_false]
  exact release_shown _ rfl (track_settles e tr base hD) (Rat.le_of_lt hD) t

/-- Same look under reduced motion. -/
theorem same_look_reduce (env : Env) (e : Entry) (tr : Tr) (base still t : Rat)
    (h : rmNopref.eval env = false) : shownIn true env e tr base still t = shownIn false env e tr base still t := by
  simp [shownIn, h]

/-- Same look at every breakpoint and time. -/
theorem same_look (env : Env) (e : Entry) (tr : Tr) (base still t : Rat) (hD : 0 < e.dur) :
    shownIn true env e tr base still t = shownIn false env e tr base still t := by
  cases h : rmNopref.eval env
  · exact same_look_reduce env e tr base still t h
  · exact same_look_motion env e tr base still t hD h

/-- Chromium holds the faithful animation layer at every time from the stage start. -/
theorem faithful_held (e : Entry) (tr : Tr) (base t : Rat) :
    chromiumHeld (track e tr base).fill (phaseAt e.delay e.dur t) = true :=
  both_held _ _ _

/-- No held layer after the end. -/
theorem no_held_after (e : Entry) (tr : Tr) (base t : Rat) (hD : 0 < e.dur) (h : e.delay + e.dur ≤ t) :
    chromiumHeld (release (track e tr base)).fill (phaseAt e.delay e.dur t) = false :=
  release_no_held_after (track e tr base) t h (Rat.le_of_lt hD)

/-- Layer-frames saved: one per sampled frame after the end. -/
theorem held_saved (e : Entry) (tr : Tr) (base : Rat) (hD : 0 < e.dur) (ts : List Rat) :
    heldFrames (release (track e tr base)) ts + (ts.filter fun t => decide (e.delay + e.dur ≤ t)).length =
      heldFrames (track e tr base) ts :=
  release_saves (track e tr base) rfl (Rat.le_of_lt hD) ts

/-- WebKit holds the same layers in both arms. -/
theorem webkit_unchanged (e : Entry) (tr : Tr) (base t : Rat) :
    webkitHeld (release (track e tr base)).fill (phaseAt e.delay e.dur t) =
      webkitHeld (track e tr base).fill (phaseAt e.delay e.dur t) :=
  webkit_same_fill _ _ _

/-- One `fill-release` rule: stage root, state classes, descendant part, keyframe, entry, transform prefix, element
classes, class count of the faithful selector and of its strongest rival. -/
structure FillRow where
  root : String
  state : String
  rest : String
  kf : String
  entry : Entry
  pre : String
  els : List String
  cls : Nat
  rival : Nat

/-- The faithful selector. -/
def FillRow.faithful (r : FillRow) : String := s!".{r.root}{r.state}{r.rest}"

/-- The variant selector: the faithful one with `.fillRelease` on the root. -/
def FillRow.variant (r : FillRow) : String := s!".{r.root}.fillRelease{r.state}{r.rest}"

/-- Class count of the variant selector. -/
def FillRow.spec (r : FillRow) : Nat := r.cls + 1

/-- Stage roots carrying `.fillRelease`. -/
def fillRoots : List String := ["profile", "secure", "invoice", "ask"]

/-- The fifteen rules, in stylesheet order. -/
def fillRows : List FillRow :=
  let sp := ":not(.isStatic).isPlay"
  let mid := "translate(-50%, -50%) "
  [⟨"profile", ":not(.isStatic).isEnter", " .phone", "profilePhoneIn", profilePhone, "", ["phone"], 4, 4⟩,
   ⟨"profile", ":not(.isStatic).isEnter", " .reviews .credCard", "credCardIn", credCard 0, "", ["credCard"], 5, 5⟩,
   ⟨"secure", sp, " .rings", "secureNetworkRingsIn", rings, "", ["rings"], 4, 4⟩,
   ⟨"secure", sp, " .faceLeft", "secureNetworkFaceLeftIn", faceLeft, "", ["face", "faceLeft"], 4, 4⟩,
   ⟨"secure", sp, " .faceRight", "secureNetworkFaceRightIn", faceRight, "", ["face", "faceRight"], 4, 4⟩,
   ⟨"secure", sp, " .dash", "secureNetworkDashIn", dash, "", ["dash", "dashLeft", "dashRight"], 4, 4⟩,
   ⟨"secure", sp, " .shield", "secureNetworkShieldIn", shield, mid, ["shield"], 4, 4⟩,
   ⟨"secure", sp, " .logoMark", "secureNetworkLogoIn", logo, mid, ["logoMark"], 4, 4⟩,
   ⟨"secure", sp, " .flag", "secureNetworkFlagIn", flag 1, "", ["flag", "flagBordered", "flagUs"], 4, 4⟩,
   ⟨"invoice", sp, " .order", "invoiceIRowIn", orderRow 0, "", ["order"], 4, 4⟩,
   ⟨"invoice", sp, " .cardEnter", "invoiceCardIn", invoiceCard, "", ["cardEnter"], 4, 4⟩,
   ⟨"ask", ":not(.isStatic).isEnter", " .askTitle", "agentsAskIn", askIn 0, "", ["askTitle"], 4, 4⟩,
   ⟨"ask", ":not(.isStatic).isEnter", " .askField", "agentsAskIn", askIn 0, "", ["askField"], 4, 4⟩,
   ⟨"ask", ":not(.isStatic).isResults", " .askList > .service", "agentsAskIn", askIn 0, "", ["service"], 5, 5⟩,
   ⟨"ask", ":not(.isStatic).isLeaving", " .askListOut .service", "agentsAskOut", askOut 0, "", ["service"], 5, 5⟩]

/-- A length as CSS: `0` bare, otherwise in px. -/
def lenCss (v : Rat) : String := if v = 0 then "0" else s!"{v}px"

/-- The transform function of a property at its to-value, if it is one. -/
def fnCss (tr : Tr) : Option String :=
  match tr.key with
  | "translateX" => some s!"translateX({lenCss tr.b})"
  | "translateY" => some s!"translateY({lenCss tr.b})"
  | "scale" => some s!"scale({tr.b})"
  | "scaleX" => some s!"scaleX({tr.b})"
  | _ => none

/-- The to-values as CSS declarations, in property order. -/
def endDecls (r : FillRow) : List (String × String) :=
  let trs := r.entry.trs
  let fil := (trs.find? (·.key == "blur")).map fun tr => ("filter", s!"blur({lenCss tr.b})")
  let op := (trs.find? (·.key == "opacity")).map fun tr => ("opacity", toString tr.b)
  let fs := trs.filterMap fnCss
  let tf := if fs.isEmpty then none else some ("transform", r.pre ++ " ".intercalate fs)
  [fil, op, tf].filterMap id

/-- The variant rule's declarations. -/
def fillDecls (r : FillRow) : List (String × String) := ("animation-fill-mode", "backwards") :: endDecls r

/-- Every variant rule outranks every rival rule on its element. -/
theorem rows_win : fillRows.all (fun r => decide (r.rival < r.spec)) = true := by decide

/-- Every row's entry has a positive duration, so `same_look` and `no_held_after` apply to it. -/
theorem rows_dur : fillRows.all (fun r => decide (0 < r.entry.dur)) = true := by decide

/-- The variant rules sit in the no-preference media block. -/
def fillMedia : String := rmNopref.css

#guard fillMedia == "(prefers-reduced-motion: no-preference)"
#guard fillRows.length == 15
#guard fillRows[0]?.map endDecls ==
  some [("filter", "blur(0)"), ("opacity", "1"), ("transform", "translateY(0) scale(1)")]
#guard fillRows[6]?.map endDecls == some [("opacity", "1"), ("transform", "translate(-50%, -50%) scale(1)")]
#guard fillRows[14]?.map endDecls == some [("opacity", "0"), ("transform", "translateY(10px)")]
#guard fillRows[9]?.map FillRow.variant == some ".invoice.fillRelease:not(.isStatic).isPlay .order"
#guard heldFrames (track profilePhone ⟨"opacity", 0, 1⟩ 1) [0, 300, 620, 1000] == 4
#guard heldFrames (release (track profilePhone ⟨"opacity", 0, 1⟩ 1)) [0, 300, 620, 1000] == 2

section MemoryTrade
open Fw.Engine.Resource

/-- A memory-only win: every gated resource keeps its sign `same` and the GPU memory falls. -/
def memoryWin (fp : Footprint) : Bool := gated.all (fun r => fp.sign r == .same) && fp.sign .gpuMem == .down

/-- A memory-only win fits any budget: the memory only falls, so `memFit` holds without a measured peak. -/
theorem memoryWin_fits (B : Nat) (fp : Footprint) (h : memoryWin fp = true) :
    memFit B (fp.sign .gpuMem) fp.peak = some true := by
  have hd : fp.sign .gpuMem = .down := by simpa [memoryWin] using (Bool.and_eq_true_iff.mp h).2
  simp [memFit, hd]

/-- The existing verdict calls a memory-only win `neutral`: it needs a gated resource that falls to say `win`. -/
theorem memoryWin_neutral (B : Nat) (fp : Footprint) (h : memoryWin fp = true) : verdict B fp = .neutral := by
  have hg : ∀ r ∈ gated, fp.sign r = .same := fun r hr => by
    simpa using List.all_eq_true.mp (Bool.and_eq_true_iff.mp h).1 r hr
  have h1 : gated.any (fp.sign · == .up) = false := List.any_eq_false.mpr fun r hr => by simp [hg r hr]
  have h2 : gated.any (fp.sign · == .unknown) = false := List.any_eq_false.mpr fun r hr => by simp [hg r hr]
  have h3 : gated.any (fp.sign · == .down) = false := List.any_eq_false.mpr fun r hr => by simp [hg r hr]
  simp [verdict, h1, h2, h3]

/-- One gated resource that is not `same` (it rose, or rose in one reading and fell in another) rules out a memory-only win. -/
theorem work_change_not_memoryWin (fp : Footprint) (r : Res) (hr : r ∈ gated) (h : fp.sign r ≠ .same) :
    memoryWin fp = false := by
  cases hm : memoryWin fp with
  | false => rfl
  | true =>
    exact absurd (by simpa using List.all_eq_true.mp (Bool.and_eq_true_iff.mp hm).1 r hr) h

/-- Chromium: layers, tiles and drawing area fall; Paint falls and RasterTask rises in every window the Lean reader decides
(run 40280497740, `windows.md`), so paint records are mixed (`unknown`) and the flag is not a memory-only win. -/
def chromiumFp : Footprint :=
  ofSigns "platform.entries:fill-release" .chromium
    ((.layers, .down) :: (.gpuMem, .down) :: (.paintRec, .unknown) :: (.repaint, .unknown) :: gatedAt .same) none

#guard memoryWin chromiumFp == false
#guard verdict budgetB chromiumFp == .open

end MemoryTrade

end FillRelease

end Fw.Parts.PlatformEntries
