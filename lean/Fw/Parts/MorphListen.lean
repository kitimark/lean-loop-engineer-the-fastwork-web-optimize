import Lean.Data.Json
import Fw.Parts.MorphMount
import Fw.Parts.MorphTween
import Fw.Device.ReplayProfiles
namespace Fw.Parts.MorphListen
open Fw.Parts

theorem armed_same (h b vh : Rat) : MorphMount.armed ⟨h, b⟩ vh = MorphTween.armed h b vh := by
  have e : vh * 45 / 100 = vh * MorphTween.fillRatio := by unfold MorphTween.fillRatio; grind
  unfold MorphMount.armed MorphTween.armed MorphTween.bottomSlack
  rw [e]

theorem active_same (w m : Rat) : MorphMount.active w m = MorphTween.active w m := by
  simp [MorphMount.active, MorphTween.active, MorphTween.activeCut]

theorem takes_same (a : Bool) (d : Rat) (g : Bool) : MorphMount.takes a d g = MorphTween.taken a d g := rfl

theorem touchDelta_same (p c : Rat) : MorphMount.touchDelta p c = p - c := rfl

def takesAny (actM actT : Bool) (d : Rat) (geomM geomT : Bool) : Bool :=
  MorphMount.takes actM d geomM || MorphTween.taken actT d geomT

theorem takesAny_disj (aM aT : Bool) (d : Rat) (gM gT : Bool) :
    takesAny aM aT d gM gT = ((aM || aT) || (decide (0 < d) && (gM || gT))) := by
  cases aM <;> cases aT <;> cases gM <;> cases gT <;> simp [takesAny, MorphMount.takes, MorphTween.taken]

theorem takesAny_one_rect (aM aT : Bool) (d h b vh : Rat) :
    takesAny aM aT d (MorphMount.armed ⟨h, b⟩ vh) (MorphTween.armed h b vh) =
      MorphTween.taken (aM || aT) d (MorphTween.armed h b vh) := by
  rw [armed_same, takesAny_disj]
  simp [MorphTween.taken]

#guard takesAny false false 5 true false == true
#guard takesAny false false (-5) true true == false
#guard takesAny false true (-5) false false == true
#guard takesAny true false 0 false false == true

inductive Who where
  | mount | tween
  deriving DecidableEq, Repr

structure Seen where
  act : Who → Bool
  geom : Who → Bool

def takesBy : Who → Seen → Rat → Bool
  | .mount, s, d => MorphMount.takes (s.act .mount) d (s.geom .mount)
  | .tween, s, d => MorphTween.taken (s.act .tween) d (s.geom .tween)

inductive Ev where
  | attach (c : Who)
  | detach (c : Who)
  | start (y : Rat)
  | move (y : Rat) (s : Seen)

structure Took where
  who : Who
  delta : Rat
  deriving DecidableEq, Repr

structure Win where
  order : List Who
  last : Who → Rat

def Win.attach (w : Win) (c : Who) : Win := if c ∈ w.order then w else { w with order := w.order ++ [c] }

def Win.detach (w : Win) (c : Who) : Win := { w with order := w.order.filter (· ≠ c) }

def Win.at (w : Win) (y : Rat) : Win := { w with last := fun c => if c ∈ w.order then y else w.last c }

def answer (w : Win) (y : Rat) (s : Seen) (c : Who) : Option Took :=
  if takesBy c s (w.last c - y) then some ⟨c, w.last c - y⟩ else none

def baseMove (w : Win) (y : Rat) (s : Seen) : List Took :=
  w.order.foldl (fun acc c => match answer w y s c with | some t => acc ++ [t] | none => acc) []

def hubMove (w : Win) (y : Rat) (s : Seen) : List Took := w.order.filterMap (answer w y s)

def run (dispatch : Win → Rat → Seen → List Took) : Win → List Ev → List (List Took)
  | _, [] => []
  | w, .attach c :: es => run dispatch (w.attach c) es
  | w, .detach c :: es => run dispatch (w.detach c) es
  | w, .start y :: es => run dispatch (w.at y) es
  | w, .move y s :: es => dispatch w y s :: run dispatch (w.at y) es

theorem foldl_answer (w : Win) (y : Rat) (s : Seen) :
    ∀ (l : List Who) (acc : List Took),
      l.foldl (fun acc c => match answer w y s c with | some t => acc ++ [t] | none => acc) acc =
        acc ++ l.filterMap (answer w y s) := by
  intro l
  induction l with
  | nil => intro acc; simp
  | cons c cs ih =>
    intro acc
    simp only [List.foldl_cons, List.filterMap_cons]
    cases h : answer w y s c <;> simp [ih]

theorem hubMove_eq_base (w : Win) (y : Rat) (s : Seen) : hubMove w y s = baseMove w y s := by
  simp [hubMove, baseMove, foldl_answer]

theorem hub_eq_base (w : Win) (es : List Ev) : run hubMove w es = run baseMove w es := by
  induction es generalizing w with
  | nil => rfl
  | cons e es ih =>
    cases e with
    | attach c => exact ih _
    | detach c => exact ih _
    | start y => exact ih _
    | move y s => simp [run, hubMove_eq_base, ih]

def prevented (ts : List Took) : Bool := !ts.isEmpty

theorem hub_prevented (w : Win) (y : Rat) (s : Seen) :
    prevented (hubMove w y s) = w.order.any fun c => takesBy c s (w.last c - y) := by
  simp only [prevented, hubMove]
  induction w.order with
  | nil => rfl
  | cons c cs ih =>
    simp only [List.filterMap_cons, answer, List.any_cons]
    cases takesBy c s (w.last c - y) <;> simp_all

theorem hub_prevented_both (w : Win) (y : Rat) (s : Seen) (ho : w.order = [.mount, .tween] ∨ w.order = [.tween, .mount])
    (hl : w.last .mount = w.last .tween) :
    prevented (hubMove w y s) =
      takesAny (s.act .mount) (s.act .tween) (w.last .tween - y) (s.geom .mount) (s.geom .tween) := by
  rw [hub_prevented]
  rcases ho with h | h <;> simp [h, takesBy, takesAny, hl, Bool.or_comm]

def listeners (merged : Bool) (w : Win) : Nat := if merged then (if w.order.isEmpty then 0 else 1) else w.order.length

theorem listeners_merged_le (w : Win) : listeners true w ≤ 1 := by
  simp only [listeners, ite_true]
  split <;> simp

inductive Mode where
  | none | watch | take
  deriving DecidableEq, Repr

def bandRootMargin : String := "1000% 0px 150% 0px"

def full (ratio : Rat) : Bool := decide (1 ≤ ratio)

def want (attached act inBand : Bool) : Mode :=
  if !attached then .none else if act || inBand then .take else .watch

def next (cur w : Mode) (down : Bool) : Mode :=
  if down && cur == .take && w == .watch then .take else w

#guard want false true true == .none
#guard want true false false == .watch
#guard want true true false == .take
#guard want true false true == .take
#guard next .take .watch true == .take
#guard next .take .watch false == .watch
#guard next .take .none true == .none
#guard next .watch .take true == .take
#guard full 1 && !full (999 / 1000)

theorem want_none (a i : Bool) : want false a i = .none := rfl

theorem want_take_act (i : Bool) : want true true i = .take := rfl

theorem want_take_band (a : Bool) : want true a true = .take := by cases a <;> rfl

theorem want_watch : want true false false = .watch := rfl

theorem next_up (cur : Mode) (d : Bool) : next cur .take d = .take := by
  cases cur <;> cases d <;> rfl

theorem next_held (w : Mode) (hw : w ≠ .watch) (cur : Mode) (d : Bool) : next cur w d = w := by
  cases cur <;> cases d <;> cases w <;> simp_all [next]

theorem next_down_take : next .take .watch true = .take := rfl

theorem next_lifted (cur w : Mode) : next cur w false = w := by
  cases cur <;> cases w <;> rfl

def edge (vhIO : Rat) : Rat := vhIO * 5 / 2

/-- `inBand` models only the 150% bottom edge of `BAND_ROOT_MARGIN`; the 1000% top edge is assumed never crossed while armed
(page below the platform shorter than 10 viewports, INFERRED, unchecked). -/
def inBand (bottom vhIO : Rat) : Bool := decide (bottom ≤ edge vhIO)

/-- Band premises: `pan` checked on the replay profiles (`#guard` on `profileLines`); `lag`, `vp`, `tall` INFERRED, unchecked. -/
structure Premise (vh vhIO bEval b0 bi : Rat) : Prop where
  pan : b0 ≤ bi + vh
  lag : bEval ≤ b0 + vh / 4
  vp : vh ≤ vhIO
  tall : 32 ≤ vh

theorem armed_in_band {h vh vhIO bEval b0 bi : Rat} (p : Premise vh vhIO bEval b0 bi)
    (ha : MorphTween.armed h bi vh = true) : inBand bEval vhIO = true := by
  have ⟨pan, lag, vp, tall⟩ := p
  simp only [MorphTween.armed, MorphTween.fillRatio, MorphTween.bottomSlack, Bool.and_eq_true] at ha
  simp only [inBand, edge]
  grind

structure Move where
  bottom : Rat
  delta : Rat
  deriving DecidableEq, Repr

def seqTakes (h vh : Rat) : Bool → List Move → List Bool
  | _, [] => []
  | a, m :: ms =>
    let t := MorphTween.taken a m.delta (MorphTween.armed h m.bottom vh)
    t :: seqTakes h vh (a || t) ms

theorem seq_quiet {h vh vhIO bEval b0 : Rat} (hout : inBand bEval vhIO = false) :
    ∀ ms : List Move, (∀ m ∈ ms, Premise vh vhIO bEval b0 m.bottom) → seqTakes h vh false ms = ms.map fun _ => false := by
  intro ms
  induction ms with
  | nil => intro _; rfl
  | cons m ms ih =>
    intro hp
    have ha : MorphTween.armed h m.bottom vh = false := by
      cases e : MorphTween.armed h m.bottom vh
      · rfl
      · have := armed_in_band (hp m (by simp)) e
        rw [hout] at this
        exact absurd this (by simp)
    have ht : MorphTween.taken false m.delta (MorphTween.armed h m.bottom vh) = false := by
      simp [MorphTween.taken, ha]
    simp only [seqTakes, ht, Bool.or_false, List.map_cons]
    exact congrArg _ (ih fun m' hm' => hp m' (by simp [hm']))

/-- A take holds iff the listener blocked at touchstart (WebPageProxy.cpp:5049-5089,5228-5300@862f17d). -/
def honored (blocking took : Bool) : Bool := blocking && took

theorem band_same {h vh vhIO bEval b0 : Rat} (act : Bool) (ms : List Move)
    (hp : ∀ m ∈ ms, Premise vh vhIO bEval b0 m.bottom) :
    (seqTakes h vh act ms).map (honored (want true act (inBand bEval vhIO) == .take)) =
      (seqTakes h vh act ms).map (honored true) := by
  cases act with
  | true => simp [want_take_act]
  | false =>
    cases hb : inBand bEval vhIO with
    | true => simp [want_take_band]
    | false =>
      rw [seq_quiet hb ms hp]
      simp [honored]

def travel : List Int → Nat
  | [] => 0
  | y0 :: ys => (ys.map fun y => (y - y0).natAbs).foldl max 0

theorem travel_mirror (h : Int) (ys : List Int) : travel (ys.map (h - ·)) = travel ys := by
  cases ys with
  | nil => rfl
  | cons y0 ys =>
    simp only [List.map_cons, travel, List.map_map]
    congr 1
    apply List.map_congr_left
    intro y _
    simp only [Function.comp]
    rw [show h - y - (h - y0) = -(y - y0) by omega, Int.natAbs_neg]

open Fw.Device.Replay in
def profilePan (p : Profile) : Bool := p.swipes.all fun s => decide (travel (s.samples.map (·.y)) ≤ 10 * p.h)

open Fw.Device.Replay in
theorem profilePan_mirror (p : Profile) (h10 : Int) :
    profilePan { p with swipes := p.swipes.map (mirror h10) } = profilePan p := by
  have e : ∀ s : Swipe, travel ((mirror h10 s).samples.map (·.y)) = travel (s.samples.map (·.y)) := by
    intro s
    rw [← travel_mirror h10 (s.samples.map (·.y))]
    simp [mirror, List.map_map, Function.comp_def]
  simp [profilePan, List.all_map, Function.comp_def, e]

open Fw.Device.Replay in
theorem profilePan_cold (p : Profile) : profilePan (cold p) = profilePan p := rfl

def profileRow (l : String) : Option (List (List Int) × Int) := do
  let j ← (Lean.Json.parse l).toOption
  let vh ← (j.getObjValD "vh").getInt?.toOption
  let ss ← (j.getObjValD "strokes").getArr?.toOption
  let ys ← ss.toList.mapM fun s => do (← s.getArr?.toOption).toList.mapM fun y => y.getInt?.toOption
  return (ys, vh)

def panRows (l : String) : Option (List Nat × Int) := (profileRow l).map fun (ys, vh) => (ys.map travel, vh)

def panOk : Option (List Nat × Int) → Bool
  | some (ts, vh) => !ts.isEmpty && ts.all fun t => decide ((t : Int) ≤ vh)
  | none => false

def profileLines : List String :=
  ((include_str "../../../packages/contracts/golden/parts/morph-listen.profiles.jsonl").splitOn "\n").filter (· ≠ "")

#guard profileLines.length == 2 && profileLines.all fun l => panOk (panRows l)
#guard panOk (panRows "{\"vh\":100,\"strokes\":[[50,151]]}") == false

def modeName : Mode → String
  | .none => "none" | .watch => "watch" | .take => "take"

def line (fn : String) (inp : List (String × Lean.Json)) (out : Lean.Json) : String :=
  (Lean.Json.mkObj [("fn", .str fn), ("in", Lean.Json.mkObj inp), ("out", out)]).compress

def bs : List Bool := [false, true]

def modes : List Mode := [.none, .watch, .take]

def ratJ (q : Rat) : Lean.Json := .num ⟨q.num * ((1000 / q.den : Nat) : Int), 3⟩

def takesAnyRows : List String :=
  bs.flatMap fun aM => bs.flatMap fun aT => [(-5 : Rat), 0, 1 / 2, 120].flatMap fun d => bs.flatMap fun gM =>
    bs.map fun gT => line "takesAny"
      [("actM", .bool aM), ("actT", .bool aT), ("delta", ratJ d), ("geomM", .bool gM), ("geomT", .bool gT)]
      (.bool (takesAny aM aT d gM gT))

def modeRows : List String :=
  (bs.flatMap fun at_ => bs.flatMap fun a => bs.map fun i =>
    line "want" [("attached", .bool at_), ("active", .bool a), ("inBand", .bool i)] (.str (modeName (want at_ a i)))) ++
  (modes.flatMap fun c => modes.flatMap fun w => bs.map fun d =>
    line "next" [("cur", .str (modeName c)), ("want", .str (modeName w)), ("down", .bool d)] (.str (modeName (next c w d)))) ++
  ([(0 : Rat), 1 / 2, 999 / 1000, 1].map fun r => line "full" [("ratio", ratJ r)] (.bool (full r))) ++
  [line "bandRootMargin" [] (.str bandRootMargin)]

def seen (aM aT gM gT : Bool) : Seen := ⟨fun | .mount => aM | .tween => aT, fun | .mount => gM | .tween => gT⟩

def evJ : Ev → Lean.Json
  | .attach c => Lean.Json.mkObj [("ev", .str "attach"), ("who", .str (whoName c))]
  | .detach c => Lean.Json.mkObj [("ev", .str "detach"), ("who", .str (whoName c))]
  | .start y => Lean.Json.mkObj [("ev", .str "start"), ("y", ratJ y)]
  | .move y s => Lean.Json.mkObj [("ev", .str "move"), ("y", ratJ y),
      ("actM", .bool (s.act .mount)), ("actT", .bool (s.act .tween)),
      ("geomM", .bool (s.geom .mount)), ("geomT", .bool (s.geom .tween))]
where whoName : Who → String | .mount => "mount" | .tween => "tween"

def tookJ (t : Took) : Lean.Json :=
  Lean.Json.mkObj [("who", .str (evJ.whoName t.who)), ("delta", ratJ t.delta)]

def runCases : List (String × List Ev) :=
  [("both-forward", [.attach .mount, .attach .tween, .start 600, .move 590 (seen false false true true),
      .move 560 (seen false true true true), .move 580 (seen false true false false)]),
   ("rest-back", [.attach .mount, .attach .tween, .start 400, .move 420 (seen false false true true),
      .move 419.5 (seen false false true true)]),
   ("tween-only", [.attach .tween, .start 500, .move 480 (seen false false false true), .attach .mount,
      .move 470 (seen false false true true)]),
   ("detach-keeps-last", [.attach .mount, .attach .tween, .start 700, .detach .mount, .move 650 (seen false false true true),
      .attach .mount, .move 640 (seen false false true true)]),
   ("order", [.attach .tween, .attach .mount, .detach .tween, .attach .tween, .start 300,
      .move 200 (seen true true false false)])]

def runRows : List String :=
  runCases.map fun (c, es) => line "run" [("case", .str c), ("events", .arr (es.map evJ).toArray)]
    (.arr ((run hubMove ⟨[], fun _ => 0⟩ es).map fun ts => Lean.Json.arr (ts.map tookJ).toArray).toArray)

def jsonl : String := String.join ((takesAnyRows ++ modeRows ++ runRows).map (· ++ "\n"))

#guard runCases.all fun (_, es) => run hubMove ⟨[], fun _ => 0⟩ es == run baseMove ⟨[], fun _ => 0⟩ es

#guard jsonl == include_str "../../../packages/contracts/golden/parts/morph-listen.jsonl"

end Fw.Parts.MorphListen
