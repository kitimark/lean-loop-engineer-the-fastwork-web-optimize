import Lean.Data.Json
import Fw.Parts.HeroExitOpt
import Fw.Parts.EngineScrollUnthrottle
import Fw.Parts.EngineScrollFollow

/-! WebKit WebAnimation.cpp:1729@862f17d keeps a finished animation on a non-monotonic timeline relevant and
AnimationTimelinesController.cpp:128-181@862f17d ticks it every frame; the park cancels it. -/
namespace Fw.Parts.ScrollPark

open Lean Fw.Parts Fw.Parts.HeroExitOpt Fw.Parts.HeroExit

inductive Fmt where
  | num
  | translateY
  | translateNarrow
  | blur
  | cardCalc
deriving Repr, DecidableEq

def ratCss (q : Rat) : String :=
  if q.den = 1 then toString q.num
  else
    let c : Int := (q * 100).num
    let w : Int := c / 100
    let f : Int := c % 100
    s!"{w}.{if f % 10 = 0 then toString (f / 10) else (if f < 10 then "0" else "") ++ toString f}"

def cardCalcCss : String :=
  "calc((1 - var(--entered)) * var(--orbit-enter-x) + var(--scatter-x)) calc((1 - var(--entered)) * var(--orbit-enter-y) + var(--scatter-y))"

def Fmt.render : Fmt → Rat → String
  | .num, q => ratCss q
  | .translateY, q => s!"translateY({ratCss q}px)"
  | .translateNarrow, q => s!"translate(-50%, {ratCss q}px)"
  | .blur, q => s!"blur({ratCss q}px)"
  | .cardCalc, _ => cardCalcCss

inductive Target where
  | copy
  | cue
  | card
deriving Repr, DecidableEq

def Target.label : Target → String
  | .copy => "copy"
  | .cue => "cue"
  | .card => "card"

structure Row where
  name : String
  prop : String
  consumer : Consumer
  fmt : Fmt

def rows (t : Target) (l : Bool) : List Row :=
  match t, l with
  | .copy, false =>
    [⟨"exitFade", "opacity", .copyOpacity 1, .num⟩, ⟨"exitCopyUp", "transform", .copyTranslateY 1 false, .translateY⟩,
     ⟨"exitBlur", "filter", .copyBlur 1 false, .blur⟩]
  | .copy, true =>
    [⟨"exitFade", "opacity", .copyOpacity 1, .num⟩, ⟨"exitCopyUpNarrow", "transform", .copyTranslateY 1 true, .translateNarrow⟩]
  | .cue, false =>
    [⟨"exitFade", "opacity", .cueOpacity, .num⟩, ⟨"exitBlur", "filter", .cueBlur, .blur⟩]
  | .cue, true =>
    [⟨"exitFade", "opacity", .cueOpacity, .num⟩, ⟨"exitCueUpNarrow", "transform", .cueTranslateY true, .translateNarrow⟩,
     ⟨"exitBlur", "filter", .cueBlur, .blur⟩]
  | .card, _ =>
    [⟨"exitCardFade", "opacity", .cardOpacity, .num⟩, ⟨"exitCardMove", "translate", .cardTranslate 1 0 1, .cardCalc⟩]

def targets : List Target := [.copy, .cue, .card]

def Target.nodes : Target → List ExitNode
  | .copy => [.copy]
  | .cue => [.cue]
  | .card => [.orbit, .deck]

theorem rows_names_eq_exitNames :
    ∀ t ∈ targets, ∀ l : Bool, ∀ n ∈ t.nodes, (rows t l).map Row.name = exitNames n l := by
  decide +kernel

def Row.fromCss (r : Row) : String := r.fmt.render (r.consumer.val 1)
def Row.toCss (r : Row) : String := r.fmt.render (r.consumer.val 0)

theorem fill_is_anim_end (k : Consumer) : k.anim 1 = k.val 0 := by
  unfold Consumer.anim lerp
  grind

theorem progress_one (T L y : Rat) (hL : 0 < L) (h : T + L ≤ y) : timelineProgress T L y = 1 := by
  unfold timelineProgress clamp01
  have h1 : L / L ≤ (y - T) / L := HeroExit.div_mono L (y - T) L hL (by grind)
  have h2 : L / L = 1 := by
    have := HeroExit.div_mul_pos L L hL
    grind
  have h3 : 1 ≤ (y - T) / L := by grind
  grind

theorem lt_bound_of_progress_ne (T L y : Rat) (hL : 0 < L) (h : timelineProgress T L y ≠ 1) : y < T + L := by
  apply Classical.byContradiction
  intro hc
  exact h (progress_one T L y hL (by grind))

theorem finished_shows_to (k : Consumer) (T h v y : Rat) (hy : T + exitRange h v ≤ y) :
    k.anim (timelineProgress T (exitRange h v) y) = k.val 0 := by
  rw [progress_one T _ y (exitRange_pos h v) hy]
  exact fill_is_anim_end k

def held (t : Target) (l : Bool) : List (String × String) := (rows t l).map fun r => (r.prop, r.toCss)

theorem held_eq_shown (t : Target) (l : Bool) (T h v y : Rat) (hy : T + exitRange h v ≤ y) :
    held t l = (rows t l).map fun r => (r.prop, r.fmt.render (r.consumer.anim (timelineProgress T (exitRange h v) y))) := by
  unfold held Row.toCss
  apply List.map_congr_left
  intro r _
  rw [finished_shows_to r.consumer T h v y hy]

theorem props_distinct : ∀ t ∈ targets, ∀ l : Bool, ((rows t l).map Row.prop).Nodup := by
  decide +kernel

theorem card_to_formula (n xe xs : Rat) : (Consumer.cardTranslate n xe xs).val 0 = (1 - n) * xe + xs := by
  simp [Consumer.val, HeroExit.cardTranslate, exitScatter]
  grind

theorem to_table_wide :
    (targets.map fun t => (rows t false).map Row.toCss) =
      [["0", "translateY(-10px)", "blur(18px)"], ["0", "blur(18px)"], ["0.65", cardCalcCss]] := by
  decide +kernel

theorem to_table_narrow :
    (targets.map fun t => (rows t true).map Row.toCss) =
      [["0", "translate(-50%, -8px)"], ["0", "translate(-50%, -10px)", "blur(18px)"], ["0.65", cardCalcCss]] := by
  decide +kernel

def bound (T h v : Rat) : Rat := T + exitRange h v

def shown (k : Consumer) (T h v : Rat) (parked : Bool) (y : Rat) : Rat :=
  if parked then k.val 0 else k.anim (timelineProgress T (exitRange h v) y)

def sentinelTopPark (h v M : Rat) : Rat := exitRange h v + M

def ioParked (T h v M yPrev : Rat) : Bool := decide (bound T h v + M < yPrev)

theorem io_no_stale (k : Consumer) (T h v M yPrev y : Rat) (hd : yPrev - y ≤ M) :
    shown k T h v (ioParked T h v M yPrev) y = k.anim (timelineProgress T (exitRange h v) y) := by
  unfold shown ioParked
  by_cases hp : bound T h v + M < yPrev
  · have hb : T + exitRange h v ≤ y := by unfold bound at hp; grind
    simp only [hp, decide_true, ↓reduceIte]
    rw [progress_one T _ y (exitRange_pos h v) hb]
    exact (fill_is_anim_end k).symm
  · simp [hp]

theorem io_restores (T h v M yPrev y : Rat) (hd : yPrev - y ≤ M)
    (hp : timelineProgress T (exitRange h v) y ≠ 1) : ioParked T h v M yPrev = false := by
  have := lt_bound_of_progress_ne T _ y (exitRange_pos h v) hp
  unfold ioParked bound
  simp only [decide_eq_false_iff_not]
  grind

def scrollParked (parkedBefore : Bool) (T h v y : Rat) : Bool := parkedBefore && decide (bound T h v ≤ y)

theorem scroll_no_stale (k : Consumer) (T h v y : Rat) (parkedBefore : Bool) :
    shown k T h v (scrollParked parkedBefore T h v y) y = k.anim (timelineProgress T (exitRange h v) y) := by
  unfold shown scrollParked
  by_cases hp : (parkedBefore && decide (bound T h v ≤ y)) = true
  · have hb : T + exitRange h v ≤ y := by
      simp only [Bool.and_eq_true, decide_eq_true_eq] at hp
      unfold bound at hp; grind
    simp only [hp, ↓reduceIte]
    rw [progress_one T _ y (exitRange_pos h v) hb]
    exact (fill_is_anim_end k).symm
  · simp [hp]

theorem scroll_restores (parkedBefore : Bool) (T h v y : Rat) (hp : timelineProgress T (exitRange h v) y ≠ 1) :
    scrollParked parkedBefore T h v y = false := by
  have := lt_bound_of_progress_ne T _ y (exitRange_pos h v) hp
  unfold scrollParked bound
  simp only [Bool.and_eq_false_iff, decide_eq_false_iff_not]
  right
  grind

def marginViewports : Nat := 1

def margin (v : Rat) : Rat := marginViewports * v

open Fw.Parts.EngineScrollUnthrottle Fw.Engine

def utStillFrames : Nat := EngineScrollFollow.stillMax

theorem utStillFrames_eq : utStillFrames = 8 := rfl

def utStillMs : Nat := (utStillFrames * 1000 + 59) / 60

theorem utStillMs_eq : utStillMs = 134 := by decide

inductive UtEv where
  | scroll
  | touch
  | still
deriving Repr, DecidableEq

def utStep : Bool → UtEv → Bool
  | _, .scroll => false
  | _, .touch => false
  | _, .still => true

theorem ut_scroll_unparks (p : Bool) : utStep p .scroll = false := rfl

theorem ut_touch_unparks (p : Bool) : utStep p .touch = false := rfl

theorem ut_park_only_still (p : Bool) (e : UtEv) (h : utStep p e = true) : e = .still := by
  cases e <;> simp_all [utStep]

theorem ut_look_identity (vp : Rect) (s : Scene) :
    Fw.Engine.visible vp (withFlag s) = Fw.Engine.visible vp s ∧ flag.readByStyle = false := by
  exact ⟨visible_withFlag vp s, flag_value_unread⟩

def utPage (supported : Bool) : Page := ⟨supported, [liftAnim]⟩

theorem parked_throttles : throttled true ⟨true, []⟩ = true := by
  simp [throttled, Page.reported, hasProgressBasedScrollDriven, Page.effective]

theorem restored_unthrottles : throttled true (utPage true) = false := by
  exact lifted_when_supported ⟨true, []⟩ rfl true

def liveAtScroll (latency lead : Nat) : Bool := decide (latency ≤ lead)

theorem live_at_scroll_iff (latency lead : Nat) : liveAtScroll latency lead = true ↔ latency ≤ lead := by
  simp [liveAtScroll]

def restoreLatency : Nat := 1

private def j (s : String) : Json := Json.str s

private def tl (l : Bool) : String := if l then "narrow" else "wide"

private def jrat (q : Rat) : Json := Json.mkObj [("num", toJson q.num), ("den", toJson (Int.ofNat q.den))]

private def samples : List (Rat × Rat × Rat × Rat × Rat) :=
  [(0, 1600, 800, 800, 801), (0, 1600, 800, 800, 799), (0, 1600, 800, 800, 5000), (300, 1600, 800, 800, 1099), (300, 1600, 800, 800, 1100),
   (300, 1600, 800, 800, 1101), (0, 1688, 844, 844, 845), (0, 100, 800, 800, 5)]

def goldenLines (_ : Unit) : List String :=
  [(Json.mkObj [("fn", "consts"), ("out", Json.mkObj [("marginViewports", marginViewports), ("utStillFrames", utStillFrames),
    ("utStillMs", utStillMs), ("restoreLatency", restoreLatency)])]).compress] ++
  (targets.flatMap fun t => [false, true].flatMap fun l => (rows t l).map fun r =>
    (Json.mkObj [("fn", "row"), ("in", Json.mkObj [("target", j t.label), ("band", j (tl l)), ("name", j r.name)]),
      ("out", Json.mkObj [("prop", j r.prop), ("from", j r.fromCss), ("to", j r.toCss)])]).compress) ++
  (targets.flatMap fun t => [false, true].map fun l =>
    (Json.mkObj [("fn", "held"), ("in", Json.mkObj [("target", j t.label), ("band", j (tl l))]),
      ("out", Json.arr ((held t l).map fun (p, c) => Json.arr #[j p, j c]).toArray)]).compress) ++
  (samples.flatMap fun (T, h, v, yPrev, y) =>
    let M := margin v
    [(Json.mkObj [("fn", "ioParked"), ("in", Json.mkObj [("T", jrat T), ("h", jrat h), ("v", jrat v), ("yPrev", jrat yPrev)]),
      ("out", Json.mkObj [("parked", ioParked T h v M yPrev), ("sentinelTop", jrat (sentinelTopPark h v M))])]).compress,
     (Json.mkObj [("fn", "scrollParked"), ("in", Json.mkObj [("T", jrat T), ("h", jrat h), ("v", jrat v), ("y", jrat y)]),
      ("out", Json.mkObj [("fromParked", scrollParked true T h v y), ("fromLive", scrollParked false T h v y)])]).compress]) ++
  (([UtEv.scroll, .touch, .still].flatMap fun e => [false, true].map fun pk =>
    (Json.mkObj [("fn", "utStep"), ("in", Json.mkObj [("event", j (match e with | .scroll => "scroll" | .touch => "touch" | .still => "still")),
      ("parked", toJson pk)]), ("out", toJson (utStep pk e))]).compress))

def goldenText (_ : Unit) : String := String.intercalate "\n" (goldenLines ()) ++ "\n"

def goldenPath : System.FilePath := ".." / "packages" / "contracts" / "golden" / "parts" / "scroll-park.jsonl"

def run (args : List String) : IO Unit := do
  match args with
  | "--check" :: _ =>
    let cur ← IO.FS.readBinFile goldenPath
    if cur.data == (goldenText ()).toUTF8.data then
      IO.eprintln s!"scroll-park golden: {goldenPath} is up to date ({(goldenLines ()).length} lines)"
    else
      throw (IO.userError s!"{goldenPath} differs from Fw.Parts.ScrollPark.goldenText")
  | _ => IO.print (goldenText ())

#guard (rows .card true).map Row.toCss == ["0.65", cardCalcCss]
#guard ioParked 0 1600 800 800 1601 == true
#guard ioParked 0 1600 800 800 1600 == false

end Fw.Parts.ScrollPark
