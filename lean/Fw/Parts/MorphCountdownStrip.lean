import Lean.Data.Json
import Fw.Parts.HeroCountdownOpt

/-! morph.countdown `strip` against `faithful`: one driver, the same face pixels per frame and digit, and the WebKit
layer count. Golden: `packages/contracts/golden/parts/morph.countdown.strip.jsonl`. -/
namespace Fw.Parts.MorphCountdownStrip

open Fw.Engine Fw.Parts.HeroCountdown Fw.Parts.HeroCountdownOpt

inductive Variant where
  | faithful
  | strip
deriving Repr, DecidableEq

structure Slot where
  spring : Spring
  target : Nat
  lastT : Rat
  animating : Bool
  cell : Rat
  started : Bool
deriving Repr, DecidableEq

def Slot.init : Slot := ⟨⟨0, 0⟩, 0, 0, false, 0, false⟩

inductive Ev where
  | refresh (secs : Nat) (now : Rat) (reduced : Bool)
  | frame (now : Rat)
  | cell (px : Rat)
deriving Repr, DecidableEq

def digitOf (secs : Nat) : Nat := secs % 60 % 10

def retarget (s : Slot) (t : Nat) (now : Rat) (reduced : Bool) : Slot × Bool :=
  if !s.started then ({ s with spring := ⟨t, 0⟩, target := t, started := true }, true)
  else if t = s.target then (s, false)
  else if reduced then ({ s with target := t, spring := ⟨t, 0⟩, animating := false }, true)
  else ({ s with target := t, spring := ⟨s.spring.value, 0⟩, lastT := now, animating := true }, false)

def stepSlot (s : Slot) (now : Rat) : Slot :=
  let r := springStep s.spring s.target (now - s.lastT)
  { s with lastT := now, spring := r.state, animating := if r.done then false else s.animating }

def upd (s : Slot) : Ev → Slot × Bool
  | .refresh secs now red => retarget s (digitOf secs) now red
  | .frame now => (stepSlot s now, true)
  | .cell px => ({ s with cell := px }, true)

def nodes : Variant → Nat
  | .faithful => 10
  | .strip => 1

def renderAt : Variant → Rat → Rat → List Rat
  | .faithful, a, c => (List.range 10).map fun (f : Nat) => faceOffsetPx f a c
  | .strip, a, c => [stripOffsetCells a * c]

def render (v : Variant) (s : Slot) : List Rat := renderAt v s.spring.value s.cell

abbrev Dom := List (Option Rat)

def write (v : Variant) (s : Slot) (d : Dom) : Dom := if 0 < s.cell then (render v s).map some else d

def drive (v : Variant) (x : Slot × Dom) (e : Ev) : Slot × Dom :=
  let r := upd x.1 e
  (r.1, if r.2 then write v r.1 x.2 else x.2)

def init (v : Variant) : Slot × Dom := (Slot.init, List.replicate (nodes v) none)

def runFrom (v : Variant) : Slot × Dom → List Ev → List (Slot × Dom)
  | x, [] => [x]
  | x, e :: es => x :: runFrom v (drive v x e) es

def run (v : Variant) (evs : List Ev) : List (Slot × Dom) := runFrom v (init v) evs

theorem drive_fst (v : Variant) (x : Slot × Dom) (e : Ev) : (drive v x e).1 = (upd x.1 e).1 := rfl

theorem runFrom_fst (v w : Variant) (evs : List Ev) :
    ∀ x y : Slot × Dom, x.1 = y.1 → (runFrom v x evs).map Prod.fst = (runFrom w y evs).map Prod.fst := by
  induction evs with
  | nil => intro x y h; simp [runFrom, h]
  | cons e es ih =>
    intro x y h
    simp only [runFrom, List.map_cons, h, List.cons.injEq, true_and]
    exact ih _ _ (by rw [drive_fst, drive_fst, h])

theorem zip_fst (v w : Variant) (evs : List Ev) :
    ∀ x y : Slot × Dom, x.1 = y.1 → ∀ p ∈ (runFrom v x evs).zip (runFrom w y evs), p.1.1 = p.2.1 := by
  induction evs with
  | nil => intro x y h p hp; simp [runFrom] at hp; rw [hp]; exact h
  | cons e es ih =>
    intro x y h p hp
    simp only [runFrom, List.zip_cons_cons, List.mem_cons] at hp
    rcases hp with rfl | hp
    · exact h
    · exact ih _ _ (by rw [drive_fst, drive_fst, h]) p hp

theorem phase_same (evs : List Ev) : (run .strip evs).map Prod.fst = (run .faithful evs).map Prod.fst :=
  runFrom_fst _ _ evs _ _ rfl

theorem upd_noWrite (s : Slot) (e : Ev) (h : (upd s e).2 = false) :
    (upd s e).1.cell = s.cell ∧ (upd s e).1.spring.value = s.spring.value := by
  cases e with
  | refresh secs now red =>
    simp only [upd, retarget] at h ⊢
    by_cases h1 : s.started <;> by_cases h2 : digitOf secs = s.target <;> cases red <;> simp_all
  | frame _ => simp [upd] at h
  | cell _ => simp [upd] at h

def Inv (v : Variant) (x : Slot × Dom) : Prop := 0 < x.1.cell → x.2 = (render v x.1).map some

theorem inv_init (v : Variant) : Inv v (init v) := by
  intro h; simp [init, Slot.init] at h

theorem inv_drive (v : Variant) (x : Slot × Dom) (e : Ev) (hx : Inv v x) : Inv v (drive v x e) := by
  intro hc
  unfold drive at hc ⊢
  dsimp only at hc ⊢
  cases hw : (upd x.1 e).2
  · obtain ⟨h1, h2⟩ := upd_noWrite x.1 e hw
    simp only [Bool.false_eq_true, ite_false]
    rw [h1] at hc
    rw [hx hc]
    simp [render, h1, h2]
  · simp [write, hc]

theorem inv_runFrom (v : Variant) (evs : List Ev) :
    ∀ x, Inv v x → ∀ y ∈ runFrom v x evs, Inv v y := by
  induction evs with
  | nil => intro x hx y hy; simp [runFrom] at hy; exact hy ▸ hx
  | cons e es ih =>
    intro x hx y hy
    simp only [runFrom, List.mem_cons] at hy
    rcases hy with rfl | hy
    · exact hx
    · exact ih _ (inv_drive v x e hx) y hy

def pxAt (d : Dom) (k : Nat) : Rat := (d.getD k none).getD 0

def domScene : Variant → DigitGeo → Dom → Scene
  | .faithful, g, d => (List.range 10).map fun (k : Nat) => (glyphId g k, glyph g k (pxAt d k / g.c))
  | .strip, g, d => (List.range 10).flatMap fun (k : Nat) =>
      (stripEntries k).map fun (j : Int) => (glyphId g k, glyph g k ((j : Rat) + pxAt d 0 / g.c))

theorem pxAt_range (f : Nat → Rat) (k : Nat) (hk : k < 10) :
    pxAt (((List.range 10).map f).map some) k = f k := by
  simp [pxAt, List.getD, hk]

theorem faithful_scene (g : DigitGeo) (s : Slot) (hc : s.cell = g.c) (h0 : g.c ≠ 0) :
    domScene .faithful g ((render .faithful s).map some) = facesDigit g s.spring.value := by
  unfold domScene facesDigit render renderAt
  apply List.map_congr_left
  intro k hk
  have hk' := List.mem_range.mp hk
  rw [pxAt_range _ k hk']
  simp only [faceOffsetPx, hc]
  rw [Rat.mul_div_cancel h0]

theorem strip_scene (g : DigitGeo) (s : Slot) (hc : s.cell = g.c) (h0 : g.c ≠ 0) :
    domScene .strip g ((render .strip s).map some) = stripDigit g s.spring.value := by
  unfold domScene stripDigit render renderAt
  simp only [pxAt, List.map_cons, List.map_nil, List.getD, List.getElem?_cons_zero, Option.getD_some, hc]
  rw [Rat.mul_div_cancel h0]

theorem dom_same (vp : Rect) (g : DigitGeo) (x y : Slot × Dom) (hx : Inv .faithful x) (hy : Inv .strip y)
    (hs : x.1 = y.1) (hc : 0 < x.1.cell) (hg : g.c = x.1.cell) :
    visible vp (domScene .strip g y.2) = visible vp (domScene .faithful g x.2) := by
  have h0 : g.c ≠ 0 := by rw [hg]; exact Rat.ne_of_gt hc
  rw [hx hc, hy (hs ▸ hc), faithful_scene g x.1 hg.symm h0, strip_scene g y.1 (hs ▸ hg.symm) h0, hs]
  exact strip_digit_same vp g y.1.spring.value

theorem same_face_px (evs : List Ev) :
    ∀ p ∈ (run .faithful evs).zip (run .strip evs), p.1.1 = p.2.1 ∧
      (0 < p.1.1.cell → ∀ vp g, g.c = p.1.1.cell →
        visible vp (domScene .strip g p.2.2) = visible vp (domScene .faithful g p.1.2)) := by
  intro p hp
  have hf := inv_runFrom .faithful evs _ (inv_init _) _ (List.of_mem_zip hp).1
  have hs := inv_runFrom .strip evs _ (inv_init _) _ (List.of_mem_zip hp).2
  have heq := zip_fst .faithful .strip evs (init .faithful) (init .strip) rfl p hp
  exact ⟨heq, fun hc vp g hg => dom_same vp g p.1 p.2 hf hs heq hc hg⟩

/-- A `will-change: transform` RenderBox composites unless Conservative off Mac (`requiresCompositingForWillChange`,
WebCore/rendering/RenderLayerCompositor.cpp:3997-4018@862f17d). -/
def composited (pol : WebKit.Policy) (active : Bool) : Bool := active && WebKit.composites pol .willChange

inductive Anc where
  | plain
  | clip
  | scroller
  | rounded
deriving Repr, DecidableEq

/-- `computeAncestorClippingStack` (RenderLayerCompositor.cpp:3651-3764@862f17d): runs of plain overflow clips merge
into one entry, a composited scroller or a rounded clip is its own entry; `true` marks a scroller entry. -/
def clipStackGo : Bool → List Anc → List Bool
  | pending, [] => if pending then [false] else []
  | pending, .plain :: as => clipStackGo pending as
  | _, .clip :: as => clipStackGo true as
  | pending, .scroller :: as => (if pending then [false] else []) ++ true :: clipStackGo false as
  | pending, .rounded :: as => (if pending then [false] else []) ++ false :: clipStackGo false as

def clipStack (as : List Anc) : List Bool := clipStackGo false as

/-- Graphics layers of a clip stack: one "ancestor clipping" layer per entry plus a "scrolling proxy" for a scroller
(`ensureClippingStackLayers`, WebCore/rendering/RenderLayerBacking.cpp:2444-2457@862f17d). -/
def stackLayers (es : List Bool) : Nat := (es.map fun b => if b then 2 else 1).sum

def countdownChain : List Anc := [.clip, .plain, .clip, .plain, .plain, .clip]

#guard clipStack countdownChain == [false]
#guard stackLayers (clipStack countdownChain) == 1
#guard clipStack [.clip, .rounded, .clip] == [false, false, false]
#guard stackLayers (clipStack [.scroller]) == 2

/-- Layers of one clock: composited RenderLayers, which the inspector census lists
(WebCore/inspector/agents/InspectorLayerTreeAgent.cpp:156-163@862f17d), and platform layers (UIViews on iOS). -/
structure Layers where
  census : Nat
  platform : Nat
deriving Repr, DecidableEq

def clockLayers (v : Variant) (pol : WebKit.Policy) (active : Bool) (n : Nat) (as : List Anc) : Layers :=
  if composited pol active then ⟨nodes v * n, nodes v * n * (1 + stackLayers (clipStack as))⟩ else ⟨0, 0⟩

theorem layers_ratio (pol : WebKit.Policy) (active : Bool) (n : Nat) (as : List Anc) :
    (clockLayers .faithful pol active n as).census = 10 * (clockLayers .strip pol active n as).census ∧
      (clockLayers .faithful pol active n as).platform = 10 * (clockLayers .strip pol active n as).platform := by
  unfold clockLayers nodes
  split <;> constructor <;> simp [Nat.mul_assoc]

theorem layers_80_to_16 :
    clockLayers .faithful .normal true 8 countdownChain = ⟨80, 160⟩ ∧
      clockLayers .strip .normal true 8 countdownChain = ⟨8, 16⟩ := by
  decide

theorem layers_7_digits :
    clockLayers .faithful .normal true 7 countdownChain = ⟨70, 140⟩ ∧
      clockLayers .strip .normal true 7 countdownChain = ⟨7, 14⟩ := by
  decide

theorem layers_conservative (v : Variant) (active : Bool) (n : Nat) (as : List Anc) :
    clockLayers v .conservative active n as = ⟨0, 0⟩ := by
  cases active <;> simp [clockLayers, composited, WebKit.composites]

theorem layers_paused (v : Variant) (pol : WebKit.Policy) (n : Nat) (as : List Anc) :
    clockLayers v pol false n as = ⟨0, 0⟩ := by
  simp [clockLayers, composited]

open Lean

def ratJ (q : Rat) : Json := .str (toString q)

def domJ (d : Dom) : Json := Json.arr (d.map fun o => match o with | some q => ratJ q | none => .null).toArray

def shown (v : Variant) (c : Rat) (d : Dom) : List (Nat × Rat) :=
  match v with
  | .faithful => ((List.range 10).map fun k => (k, pxAt d k)).filter fun p => -c < p.2 && p.2 < c
  | .strip => (List.range 10).flatMap fun (k : Nat) =>
      ((stripEntries k).map fun (j : Int) => (k, (j : Rat) * c + pxAt d 0)).filter fun p => -c < p.2 && p.2 < c

def shownJ (l : List (Nat × Rat)) : Json := Json.arr (l.map fun p => Json.arr #[Json.num ⟨p.1, 0⟩, ratJ p.2]).toArray

def springs : List Rat := [0, 1 / 4, 1 / 2, 3, 37 / 2, 39 / 4, -1 / 2, 99 / 10, 10, -1 / 1000]

def cells : List Rat := [31, 36, 52]

def offsetRow (a c : Rat) : Json :=
  let s : Slot := { Slot.init with spring := ⟨a, 0⟩, cell := c }
  let df := (render .faithful s).map some
  let ds := (render .strip s).map some
  Json.mkObj [("kind", "offset"), ("spring", ratJ a), ("cell", ratJ c), ("faithful", domJ df), ("strip", domJ ds),
    ("shownFaithful", shownJ (shown .faithful c df)), ("shownStrip", shownJ (shown .strip c ds))]

#guard springs.all fun a => cells.all fun c =>
  let s : Slot := { Slot.init with spring := ⟨a, 0⟩, cell := c }
  shown .faithful c ((render .faithful s).map some) == shown .strip c ((render .strip s).map some)

def evJ : Ev → Json
  | .refresh secs now red => Json.mkObj [("refresh", Json.num ⟨secs, 0⟩), ("now", ratJ now), ("reduced", .bool red)]
  | .frame now => Json.mkObj [("frame", ratJ now)]
  | .cell px => Json.mkObj [("cell", ratJ px)]

def frames (t0 : Rat) (dts : List Rat) : List Ev :=
  (dts.foldl (fun (acc : Rat × List Ev) dt => (acc.1 + dt, acc.2 ++ [.frame (acc.1 + dt)])) (t0, [])).2

def scenarios : List (String × List Ev) :=
  [("ones", [.refresh 125 0 false, .cell 52, .refresh 124 1000 false] ++ frames 1000 (List.replicate 8 16)),
   ("wrap", [.refresh 120 0 false, .cell 31, .refresh 119 1000 false] ++ frames 1000 (List.replicate 6 16)),
   ("reduced", [.refresh 125 0 true, .cell 36, .refresh 124 1000 true, .frame 1016]),
   ("nocell", [.refresh 125 0 false, .refresh 124 1000 false] ++ frames 1000 [16, 16, 16]),
   ("restart", [.refresh 125 0 false, .cell 52, .refresh 124 1000 false] ++ frames 1000 [16, 16] ++
     [.refresh 123 1040 false] ++ frames 1040 [16, 16, 16]),
   ("gaps", [.refresh 117 0 false, .cell 36, .refresh 116 1000 false] ++ frames 1000 [33, 7, 50, 16])]

def stateJ (fa st : Slot × Dom) : Json :=
  Json.mkObj [("value", ratJ fa.1.spring.value), ("velocity", ratJ fa.1.spring.velocity),
    ("target", Json.num ⟨fa.1.target, 0⟩), ("animating", .bool fa.1.animating), ("faithful", domJ fa.2),
    ("strip", domJ st.2), ("shownFaithful", shownJ (shown .faithful fa.1.cell fa.2)),
    ("shownStrip", shownJ (shown .strip st.1.cell st.2))]

def driveRow (sc : String × List Ev) : Json :=
  let fa := (run .faithful sc.2).drop 1
  let st := (run .strip sc.2).drop 1
  Json.mkObj [("kind", "drive"), ("scenario", .str sc.1), ("events", Json.arr (sc.2.map evJ).toArray),
    ("after", Json.arr ((fa.zip st).map fun p => stateJ p.1 p.2).toArray)]

#guard scenarios.all fun sc => ((run .faithful sc.2).zip (run .strip sc.2)).all fun p =>
  p.1.1 == p.2.1 && shown .faithful p.1.1.cell p.1.2 == shown .strip p.2.1.cell p.2.2

def layersRow (n : Nat) (pol : WebKit.Policy) (active : Bool) : Json :=
  let l (v : Variant) := clockLayers v pol active n countdownChain
  Json.mkObj [("kind", "layers"), ("digits", Json.num ⟨n, 0⟩),
    ("policy", .str (match pol with | .normal => "normal" | .conservative => "conservative")), ("active", .bool active),
    ("faithful", Json.mkObj [("census", Json.num ⟨(l .faithful).census, 0⟩), ("platform", Json.num ⟨(l .faithful).platform, 0⟩)]),
    ("strip", Json.mkObj [("census", Json.num ⟨(l .strip).census, 0⟩), ("platform", Json.num ⟨(l .strip).platform, 0⟩)])]

def goldenLines (_ : Unit) : List String :=
  (springs.flatMap fun a => cells.map fun c => (offsetRow a c).compress) ++
  scenarios.map (fun sc => (driveRow sc).compress) ++
  ([(8, .normal, true), (7, .normal, true), (8, .normal, false), (8, .conservative, true)] : List (Nat × WebKit.Policy × Bool)).map
    fun r => (layersRow r.1 r.2.1 r.2.2).compress

def jsonl (_ : Unit) : String := String.join ((goldenLines ()).map (· ++ "\n"))

#guard jsonl () == include_str "../../../packages/contracts/golden/parts/morph.countdown.strip.jsonl"

end Fw.Parts.MorphCountdownStrip
